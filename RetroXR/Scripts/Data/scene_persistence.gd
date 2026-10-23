## ScenePersistence — saves and restores dynamically-spawned objects for one room.
## Objects must be in the "spawned" group to be tracked.
##
## Save directory: user://scenes/{room}/
## Manifest:       user://scenes/{room}/manifest.json
## Slot files:     user://scenes/{room}/{id}.json
## Slot pictures:  user://scenes/{room}/{id}.png  (SceneThumbnail)
##
## Each room keeps its own slots and its own manifest. They cannot be one set: a
## slot is a list of world poses, and the arcade's are struck against the arcade's
## furniture — restoring them into passthrough would rain a room's contents into
## wherever the player happens to be standing. The room is a constructor argument
## rather than a parameter on every call because one instance is only ever used
## against one room, and SceneManager.room_has_slots decides which rooms keep them.
class_name ScenePersistence
extends RefCounted


## How far an async restore has got, so a loading screen can say "14 of 31"
## instead of spinning. Only instantiate_objects_async() emits it; the
## synchronous variant finishes inside one frame and has nothing to report.
signal restore_progress(done: int, total: int)


const ROOMS_DIR     := "user://scenes"
const DEFAULT_ROOM  := "arcade"
## The arcade's own directory, named because the save/restore probes reach for it.
const ARCADE_DIR    := "user://scenes/arcade"
const VERSION       := 2
## How long the async restore may hold the main thread before yielding a frame.
const FRAME_BUDGET_USEC := 4000

const _STRING_FIELDS := [
	"systemid", "model_id", "model_variant", "tv_model", "rom_path", "game_label", "save_id",
	"cart_systemid", "card_id", "card_label", "pdf_path", "scene", "video_path",
	"video_label", "dvd_path", "dvd_label", "album_path", "album_label", "kind",
	"pad_guid", "pad_name", "image_path", "core_name",
	# Which expansion a unit is -- a key in ExpansionCatalog.ROWS.
	"expansion_id",
	# The image of the memory built into a console -- see ConsoleMemory.
	"console_memory",
	# What a player forced at spawn: a cartridge's shell (a preset, or a colour
	# they mixed), an N64's regional body, and the colour of a lead's plugs.
	# Absent means the object's own.
	"shell_preset", "shell_color", "body_region", "plug_color",
	# The market a cartridge whose ROM names none fell back to, pinned so a
	# region change does not swap its body (RetroCartridge.fallback_market).
	"fallback_market",
]
const _NUMBER_FIELDS := [
	"lid_angle", "scale_factor", "stereo_mode", "size_scale", "page_state",
	"page_leaf", "sensitivity", "stick_distance", "device_type", "port_index",
	"volume", "cords",
	"pad_ordinal", "fit_mode", "roll",
	# A multitap's SELECT switch: 2 or 5 (RetroMultitap.MODE_2P / MODE_5P).
	"tap_mode",
	# A cabinet's own say over the arcade attract option -- see RetroSystem.attract_override.
	"attract",
	# The length a player forced on a lead at spawn, in metres. Absent means the
	# scene's own -- see CompositeCable.cord_length.
	"cord_length",
]
const _BOOL_FIELDS := ["video_out", "ignore_gravity", "crt_enabled", "half_pages", "stuck",
	"locked", "hardback", "sticks", "cabinet_art", "attract_on",
	# A GBA SP's light switch (RetroSystem.get_screen_light); absent = on.
	"screen_light",
	# A reflective-LCD handheld's "Self-Lit Screen" (RetroSystem.get_screen_glow);
	# absent = off.
	"screen_glow",
	# A mixed shell colour forced as metal flake -- see RetroCartridge.shell_flake.
	"shell_flake"]
const _REFERENCE_FIELDS := [
	"tv", "cartridge", "memcard", "tape", "disc", "media", "system",
	"nunchuk", "motion_plus", "expansion_cover", "pak", "gb_cart",
	# The clip-on accessory on an expansion unit -- the 32X's Model 2 spacer.
	"accessory",
	# An arcade cabinet's bay, and the board standing in a bay.
	"bay", "board",
]
## Stamped on a mod prop when it spawns, so serialize_node can recognise it
## without a class to test against. The value is the registered type string.
const MOD_TYPE_META := &"mod_object_type"
## A snap zone a mod put somewhere that is not its own prop -- hung on a shipped
## object by a hook, or authored in a mod's room. Whatever it holds is saved as
## held there (see _attachment_field).
const MOD_ZONE_GROUP := &"mod_zone"

## type -> {scene: String, owner: String}, contributed by mods.
##
## The type string is written into save slots, so it is permanent once a player
## has used it: renaming one orphans every object of that type in every slot.
static var _mod_objects: Dictionary = {}


## Register a mod prop. Returns "" on success.
static func register_mod_object(type: String, scene_path: String, owner_id: String) -> String:
	if PLAIN_SCENES.has(type) or _LOAD_KINDS.has(type):
		return "'%s' is a shipped object type" % type
	if _mod_objects.has(type):
		return "'%s' is already registered by mod '%s'" % [type, _mod_objects[type].get("owner", "?")]
	# ResourceLoader, not FileAccess: a res:// path inside a mounted pack is
	# remapped, and FileAccess.file_exists reports false for every one of them.
	if not ResourceLoader.exists(scene_path):
		return "scene does not exist: %s" % scene_path
	_mod_objects[type] = {"scene": scene_path, "owner": owner_id}
	return ""


static func is_mod_object(type: String) -> bool:
	return _mod_objects.has(type)


## Every object type a mod registered.
static func mod_object_types() -> Array:
	return _mod_objects.keys()


static func mod_object_scene(type: String) -> String:
	return str((_mod_objects.get(type, {}) as Dictionary).get("scene", ""))


static func drop_mod_objects(owner_id: String) -> void:
	for type: String in _mod_objects.keys():
		if _mod_objects[type].get("owner", "") == owner_id:
			_mod_objects.erase(type)


## Build a registered mod prop and stamp it so it serializes back as itself.
## Build one of the plain object types from its token, or null for a type this
## table does not carry.
##
## Public because the spawn menu needs the same answer: it used to keep its own
## preload of each of these scenes and its own match arm naming the same token,
## so a new prop had to be registered twice and an object registered once either
## vanished on the next load or could not be spawned at all.
static func instantiate(type: String) -> Node3D:
	var packed: PackedScene = PLAIN_SCENES.get(type, LEAD_SCENES.get(type, null))
	if packed == null:
		return null
	return packed.instantiate() as Node3D


static func _instantiate_mod_object(type: String) -> Node3D:
	var path := mod_object_scene(type)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		return null
	var obj := packed.instantiate() as Node3D
	if obj != null:
		obj.set_meta(MOD_TYPE_META, type)
	return obj


## Bumped by every async restore as it starts. Because those yield frames, a
## second one can begin — a room change auto-loading a slot on top of a slot the
## player picked from the menu — and the two then build into the same room while
## clear_scene() frees what the other just spawned, leaving live systems holding
## freed cable plugs. The older run checks this after each yield and stands down.
static var _restore_generation := 0

const SYSTEM_SCENE           := preload("res://Scenes/Objects/system.tscn")
const EXPANSION_SCENE        := preload("res://Scenes/Objects/expansion.tscn")
const EXPANSION_COVER_SCENE  := preload("res://Scenes/Objects/expansion_cover.tscn")
const PORT_COVER_SCENE       := preload("res://Scenes/Objects/port_cover.tscn")
const TV_SCENE               := preload("res://Scenes/Objects/tv.tscn")
const CART_SCENE             := preload("res://Scenes/Objects/media/cartridge.tscn")
const DISC_SCENE             := preload("res://Scenes/Objects/media/disc.tscn")
const UMD_DISC_SCENE         := preload("res://Scenes/Objects/media/umd_disc.tscn")
const MEMCARD_SCENE          := preload("res://Scenes/Objects/media/memory_card.tscn")
const GC_MEMCARD_SCENE       := preload("res://Scenes/Objects/media/gc_memory_card.tscn")
const PS2_MEMCARD_SCENE      := preload("res://Scenes/Objects/media/ps2_memory_card.tscn")
const BOOK_SCENE             := preload("res://Scenes/Objects/media/pdf_book.tscn")
const POSTER_SCENE           := preload("res://Scenes/Objects/media/poster.tscn")
const RETRO_CONTROLLER_SCENE := preload("res://Scenes/Objects/controllers/retro_controller.tscn")
const LIGHT_GUN_SCENE        := preload("res://Scenes/Objects/peripherals/light_gun.tscn")
const RETRO_MULTITAP_SCENE   := preload("res://Scenes/Objects/controllers/retro_multitap.tscn")
const VCR_SCENE              := preload("res://Scenes/Objects/appliances/vcr_player.tscn")
const TAPE_SCENE             := preload("res://Scenes/Objects/media/vcr_tape.tscn")
const DVD_SCENE              := preload("res://Scenes/Objects/appliances/dvd_player.tscn")
const DVD_DISC_SCENE         := preload("res://Scenes/Objects/media/dvd_disc.tscn")
const CD_PLAYER_SCENE        := preload("res://Scenes/Objects/appliances/cd_player.tscn")
const CASSETTE_PLAYER_SCENE  := preload("res://Scenes/Objects/appliances/cassette_player.tscn")
const AUDIO_DISC_SCENE       := preload("res://Scenes/Objects/media/audio_disc.tscn")
const AUDIO_CASSETTE_SCENE   := preload("res://Scenes/Objects/media/audio_cassette.tscn")
const RECORD_PLAYER_SCENE    := preload("res://Scenes/Objects/appliances/record_player.tscn")
const VINYL_RECORD_SCENE     := preload("res://Scenes/Objects/media/vinyl_record.tscn")
const TV_REMOTE_SCENE        := preload("res://Scenes/Objects/appliances/tv_remote.tscn")
const COMPOSITE_CABLE_SCENE  := preload("res://Scenes/Objects/cables/composite_cable.tscn")
const MONO_CABLE_SCENE       := preload("res://Scenes/Objects/cables/mono_composite_cable.tscn")
const WII_AV_CABLE_SCENE     := preload("res://Scenes/Objects/system_models/wii/wii_av_cable.tscn")
const N64_AV_CABLE_SCENE     := preload("res://Scenes/Objects/system_models/nintendo_64/n64_av_cable.tscn")
const GENESIS_AV_CABLE_SCENE := preload("res://Scenes/Objects/system_models/genesis/genesis_av_cable.tscn")
const PS2_AV_CABLE_SCENE     := preload("res://Scenes/Objects/cables/ps2_av_cable.tscn")
const DC_AV_CABLE_SCENE      := preload("res://Scenes/Objects/system_models/dreamcast/dc_av_cable.tscn")
const VGA_CABLE_SCENE        := preload("res://Scenes/Objects/cables/vga_cable.tscn")
const TRS_CABLE_SCENE        := preload("res://Scenes/Objects/cables/trs_cable.tscn")
const SP_PHONES_ADAPTER_SCENE := preload("res://Scenes/Objects/cables/sp_phones_adapter.tscn")
const LINK_CABLE_SCENE       := preload("res://Scenes/Objects/cables/link_cable.tscn")
const GB_LINK_CABLE_SCENE    := preload("res://Scenes/Objects/cables/gb_link_cable.tscn")
const DMG_LINK_CABLE_SCENE   := preload("res://Scenes/Objects/cables/dmg_link_cable.tscn")
const GB_LINK_ADAPTER_SCENE  := preload("res://Scenes/Objects/cables/gb_link_adapter.tscn")
const GG_LINK_CABLE_SCENE    := preload("res://Scenes/Objects/cables/gg_link_cable.tscn")
const WS_LINK_CABLE_SCENE    := preload("res://Scenes/Objects/cables/ws_link_cable.tscn")
const NGP_LINK_CABLE_SCENE   := preload("res://Scenes/Objects/cables/ngp_link_cable.tscn")
const VB_LINK_CABLE_SCENE    := preload("res://Scenes/Objects/cables/vb_link_cable.tscn")
const COMLYNX_CABLE_SCENE    := preload("res://Scenes/Objects/cables/comlynx_cable.tscn")
const GC_GBA_CABLE_SCENE     := preload("res://Scenes/Objects/cables/gc_gba_cable.tscn")
const PSX_LINK_CABLE_SCENE   := preload("res://Scenes/Objects/cables/psx_link_cable.tscn")
const SATURN_LINK_CABLE_SCENE := preload("res://Scenes/Objects/cables/saturn_link_cable.tscn")
const JAG_LINK_CABLE_SCENE  := preload("res://Scenes/Objects/cables/jag_link_cable.tscn")
const ILINK_CABLE_SCENE      := preload("res://Scenes/Objects/cables/ilink_cable.tscn")
const ILINK_HUB_SCENE        := preload("res://Scenes/Objects/cables/ilink_hub.tscn")
const GB_PRINTER_SCENE       := preload("res://Scenes/Objects/peripherals/gb_printer.tscn")
const ETHERNET_CABLE_SCENE   := preload("res://Scenes/Objects/cables/ethernet_cable.tscn")
const ETHERNET_HUB_SCENE     := preload("res://Scenes/Objects/cables/ethernet_hub.tscn")

const JAMMA_CABLE_SCENE      := preload("res://Scenes/Objects/cables/jamma_cable.tscn")
const ARCADE_BAY_JAMMA_SCENE := preload("res://Scenes/Objects/peripherals/arcade_bay_jamma.tscn")
const ARCADE_BAY_MVS_SCENE   := preload("res://Scenes/Objects/peripherals/arcade_bay_mvs.tscn")
const ARCADE_BAY_LASERDISC_SCENE := preload("res://Scenes/Objects/peripherals/arcade_bay_laserdisc.tscn")
const ARCADE_BAY_DISCRETE_SCENE := preload("res://Scenes/Objects/peripherals/arcade_bay_discrete.tscn")
const POWER_CORD_SCENE       := preload("res://Scenes/Objects/cables/power_cord.tscn")
const POWER_STRIP_SCENE      := preload("res://Scenes/Objects/appliances/power_strip.tscn")
const TRAVEL_ADAPTER_SCENE   := preload("res://Scenes/Objects/appliances/travel_adapter.tscn")
const NEMA_1_15_C7_CORD_SCENE := preload(
	"res://Scenes/Objects/cables/nema_1_15_to_c7_cord.tscn")
const NEMA_1_15_C7P_CORD_SCENE := preload(
	"res://Scenes/Objects/cables/nema_1_15_polarized_to_c7_polarized_cord.tscn")
const SPEAKER_PAIR_SCENE     := preload("res://Scenes/Objects/appliances/speaker_pair.tscn")
const LOUDSPEAKER_SCENE      := preload("res://Scenes/Objects/appliances/loudspeaker.tscn")
const SUBWOOFER_SCENE        := preload("res://Scenes/Objects/appliances/subwoofer.tscn")
const SURROUND_AMP_SCENE     := preload("res://Scenes/Objects/appliances/surround_amp.tscn")
const SPEAKER_STAND_120      := preload("res://Scenes/Objects/appliances/speaker_stand_120.tscn")
const SPEAKER_STAND_100      := preload("res://Scenes/Objects/appliances/speaker_stand_100.tscn")
const CONSOLE_STAND_SCENE    := preload("res://Scenes/Objects/stands/console_stand.tscn")
const SPEAKER_CABLE_SCENE    := preload("res://Scenes/Objects/cables/speaker_cable.tscn")
const STORAGE_BOX_SCENE      := preload("res://Scenes/Objects/appliances/storage_box.tscn")
const TABLE_SCENE            := preload("res://Scenes/Objects/furniture/table.tscn")
const RETRO_MOUSE_SCENE      := preload("res://Scenes/Objects/peripherals/retro_mouse.tscn")
const SNES_MOUSE_SCENE       := preload("res://Scenes/Objects/peripherals/snes_mouse.tscn")
const RETRO_KEYBOARD_SCENE   := preload("res://Scenes/Objects/peripherals/retro_keyboard.tscn")
const WIIMOTE_SCENE          := preload("res://Scenes/Objects/controllers/wii/wiimote.tscn")
const NUNCHUK_SCENE          := preload("res://Scenes/Objects/controllers/wii/nunchuk.tscn")
const MOTION_PLUS_SCENE      := preload("res://Scenes/Objects/controllers/wii/motion_plus.tscn")
const RUMBLE_PAK_SCENE       := preload("res://Scenes/Objects/controllers/n64/rumble_pak.tscn")
const SEGA32X_SPACER_SCENE   := preload("res://Scenes/Objects/peripherals/sega32x_spacer.tscn")
const CONTROLLER_PAK_SCENE   := preload("res://Scenes/Objects/controllers/n64/controller_pak.tscn")
const VMU_SCENE              := preload("res://Scenes/Objects/controllers/dreamcast/vmu_card.tscn")
const JUMP_PACK_SCENE        := preload("res://Scenes/Objects/controllers/dreamcast/jump_pack.tscn")
const BATTERY_AA_SCENE       := preload("res://Scenes/Objects/batteries/battery_aa.tscn")
const BATTERY_AAA_SCENE      := preload("res://Scenes/Objects/batteries/battery_aaa.tscn")
const XBOX_MU_SCENE          := preload("res://Scenes/Objects/controllers/xbox/xbox_mu.tscn")
const DC_MICROPHONE_SCENE    := preload("res://Scenes/Objects/controllers/dreamcast/dc_microphone.tscn")
const GC_MICROPHONE_SCENE    := preload("res://Scenes/Objects/controllers/gamecube/gc_microphone.tscn")
const N64_VRU_SCENE          := preload("res://Scenes/Objects/controllers/n64/n64_vru.tscn")
const TRANSFER_PAK_SCENE     := preload("res://Scenes/Objects/controllers/n64/transfer_pak.tscn")
const SENSOR_BAR_SCENE       := preload("res://Scenes/Objects/system_models/wii/sensor_bar.tscn")
const RF_SWITCH_SCENE        := preload("res://Scenes/Objects/appliances/rf_switch.tscn")
const ANTENNA_SCENE          := preload("res://Scenes/Objects/appliances/antenna.tscn")
const PAD_RECEIVER_SCENE     := preload("res://Scenes/Objects/controllers/pad_receiver.tscn")
const KEYBOARD_RECEIVER_SCENE := preload("res://Scenes/Objects/controllers/keyboard_receiver.tscn")
const MOUSE_RECEIVER_SCENE    := preload("res://Scenes/Objects/controllers/mouse_receiver.tscn")

## Types whose entry carries nothing but a pose — instantiate and place, no
## properties to apply. Types that need more are match arms in
## deserialize_object().
##
## One of THREE places an interactive object is registered, and they must be
## edited together or the object half-exists:
##   1. this table (or a deserialize_object arm) — restoring it from a save,
##      plus its row in _save_kind_rows — writing it (scene_tests registry/
##      fails a PLAIN_SCENES type no row writes)
##   2. spawn_menu_controller.gd's `match type` — spawning it from the menu
##   3. net_events.gd's EV_* kinds — announcing what a player does to it
## The keys here and in (2) are deliberately the same strings; an object that
## spawns but is missing from (1) vanishes on the next load, and one missing
## from (2) can only ever arrive from a save file.
## Every lead in the room is a CompositeCable; only the scene it was spawned
## from differs. Keyed by the "kind" a cord serializes as, which is the SAME
## token the spawn menu offers — so a new lead is one row here rather than a row
## in this file and a match arm in spawn_menu_controller, which is how the two
## sides used to drift.
##
## rf_switch is in here despite not being a cord: it is a lead with a box in the
## middle, and it spawns and restores as one. antenna likewise: a lead with a body
## on one END, whose other end is the only connector it has.
const LEAD_SCENES := {
	"wii_av_cable": WII_AV_CABLE_SCENE,
	"n64_av_cable": N64_AV_CABLE_SCENE,
	"genesis_av_cable": GENESIS_AV_CABLE_SCENE,
	"dc_av_cable": DC_AV_CABLE_SCENE,
	"ps2_av_cable": PS2_AV_CABLE_SCENE,
	"vga_cable": VGA_CABLE_SCENE,
	"trs_cable": TRS_CABLE_SCENE,
	"sp_phones_adapter": SP_PHONES_ADAPTER_SCENE,
	"link_cable": LINK_CABLE_SCENE,
	"gb_link_cable": GB_LINK_CABLE_SCENE,
	"dmg_link_cable": DMG_LINK_CABLE_SCENE,
	"gb_link_adapter": GB_LINK_ADAPTER_SCENE,
	"gg_link_cable": GG_LINK_CABLE_SCENE,
	"ws_link_cable": WS_LINK_CABLE_SCENE,
	"ngp_link_cable": NGP_LINK_CABLE_SCENE,
	"vb_link_cable": VB_LINK_CABLE_SCENE,
	"comlynx_cable": COMLYNX_CABLE_SCENE,
	"gc_gba_cable": GC_GBA_CABLE_SCENE,
	"psx_link_cable": PSX_LINK_CABLE_SCENE,
	"saturn_link_cable": SATURN_LINK_CABLE_SCENE,
	"jag_link_cable": JAG_LINK_CABLE_SCENE,
	"ilink_cable": ILINK_CABLE_SCENE,
	"ethernet_cable": ETHERNET_CABLE_SCENE,

	# A JAMMA harness lead: a cabinet's back socket to a bay's.
	"jamma_cable": JAMMA_CABLE_SCENE,
	"rf_switch": RF_SWITCH_SCENE,
	"antenna": ANTENNA_SCENE,
	# A headset whose captive cord ends in a 3.5 mm plug (Headphones): a lead with a body on one end, like the aerial.
	"headphones": preload("res://Scenes/Objects/appliances/headphones.tscn"),
	"power_cord": POWER_CORD_SCENE,
	"power_strip": POWER_STRIP_SCENE,
	"travel_adapter": TRAVEL_ADAPTER_SCENE,
	"nema_1_15_to_c7_cord": NEMA_1_15_C7_CORD_SCENE,
	"nema_1_15_polarized_to_c7_polarized_cord": NEMA_1_15_C7P_CORD_SCENE,
	# The other mains regions' leads (MainsRegions.CORDS), baked by
	# Tools/gen/gen_mains_cords.gd from the two above.
	"cee_7_7_cord": preload("res://Scenes/Objects/cables/cee_7_7_cord.tscn"),
	"europlug_c7_cord": preload("res://Scenes/Objects/cables/europlug_c7_cord.tscn"),
	"bs_1363_cord": preload("res://Scenes/Objects/cables/bs_1363_cord.tscn"),
	"bs_1363_c7_cord": preload("res://Scenes/Objects/cables/bs_1363_c7_cord.tscn"),
	"as_3112_cord": preload("res://Scenes/Objects/cables/as_3112_cord.tscn"),
	"as_3112_c7_cord": preload("res://Scenes/Objects/cables/as_3112_c7_cord.tscn"),
	"sev_1011_cord": preload("res://Scenes/Objects/cables/sev_1011_cord.tscn"),
	"cei_23_50_cord": preload("res://Scenes/Objects/cables/cei_23_50_cord.tscn"),
	"ds_k_cord": preload("res://Scenes/Objects/cables/ds_k_cord.tscn"),
	"sans_164_2_cord": preload("res://Scenes/Objects/cables/sans_164_2_cord.tscn"),
	"nbr_14136_cord": preload("res://Scenes/Objects/cables/nbr_14136_cord.tscn"),
	"bs_546_cord": preload("res://Scenes/Objects/cables/bs_546_cord.tscn"),
	"is_1293_cord": preload("res://Scenes/Objects/cables/is_1293_cord.tscn"),
	"si_32_cord": preload("res://Scenes/Objects/cables/si_32_cord.tscn"),
	"speaker_cable": SPEAKER_CABLE_SCENE,
	"mono_composite_cable": MONO_CABLE_SCENE,
	"composite_cable": COMPOSITE_CABLE_SCENE,
}


const PLAIN_SCENES := {
	"tv_remote": TV_REMOTE_SCENE,
	"loudspeaker": LOUDSPEAKER_SCENE,
	"subwoofer": SUBWOOFER_SCENE,
	"surround_amp": SURROUND_AMP_SCENE,
	# Tokens name the height in centimetres, so a third stand is a third row
	# rather than a rename of these two.
	"speaker_stand_120": SPEAKER_STAND_120,
	"speaker_stand_100": SPEAKER_STAND_100,
	"trash_can": STORAGE_BOX_SCENE,
	"table": TABLE_SCENE,
	# Pose only: the hub has no state of its own. Which lead is in which of its
	# sockets is recorded by each LEAD, naming this hub and "PortN".
	"ilink_hub": ILINK_HUB_SCENE,
	# Pose only, like the hub: the lead in its EXT.IN socket is saved by the LEAD,
	# and it comes back switched off. Paper already torn off is a poster of its own.
	"gb_printer": GB_PRINTER_SCENE,
	# Pose only, for the i.LINK hub's reason.
	"ethernet_hub": ETHERNET_HUB_SCENE,

	# The arcade cabinet's bay, one scene per kind. A pose and the board standing in it; which cabinet
	# plays from it is recorded on the CABINET's entry ("bay"), or by a JAMMA lead's plug.
	"arcade_bay_jamma": ARCADE_BAY_JAMMA_SCENE,
	"arcade_bay_mvs": ARCADE_BAY_MVS_SCENE,
	"arcade_bay_laserdisc": ARCADE_BAY_LASERDISC_SCENE,
	"arcade_bay_discrete": ARCADE_BAY_DISCRETE_SCENE,
	"light_gun": LIGHT_GUN_SCENE,
	# Slots written before the rename say "ray_gun".
	"ray_gun": LIGHT_GUN_SCENE,
	"retro_keyboard": RETRO_KEYBOARD_SCENE,
	"vcr_player": VCR_SCENE,
	"dvd_player": DVD_SCENE,
	"cd_player": CD_PLAYER_SCENE,
	"record_player": RECORD_PLAYER_SCENE,
	"cassette_player": CASSETTE_PLAYER_SCENE,
	# Both Wii objects instantiate from here; the remote's pairing and its seated
	# Nunchuk are applied afterwards by the peripheral arm of _apply_references,
	# exactly as the light gun's port connection is. The Nunchuk carries no port of
	# its own — it is wired to a remote, and that seating is restored from the
	# REMOTE's entry, not from this one.
	"wiimote": WIIMOTE_SCENE,
	"nunchuk": NUNCHUK_SCENE,
	# Same arrangement for the dongle: a pose here, and the fact that it is seated
	# in a particular remote restored from the REMOTE's entry.
	"motion_plus": MOTION_PLUS_SCENE,
	# The three N64 paks take the dongle's arrangement above: a pose here, and
	# which controller each is seated in restored from that CONTROLLER's entry.
	# The Controller Pak carries card fields on top of the pose (_card_fields on
	# save, _PLAIN_CARD_LABELS on load); all three are instantiated from here.
	"rumble_pak": RUMBLE_PAK_SCENE,
	"controller_pak": CONTROLLER_PAK_SCENE,
	# The 32X's Model 2 spacer: a pose here, and which 32X it is clipped to
	# restored from that UNIT's entry ("accessory"), as the paks are from their
	# controller's.
	"sega32x_spacer": SEGA32X_SPACER_SCENE,
	"transfer_pak": TRANSFER_PAK_SCENE,
	# The Dreamcast's VMU is the same shape of thing as the Controller Pak — a
	# card that seats in a controller — so it carries card fields on top of the
	# pose too.
	"vmu": VMU_SCENE,
	# The Xbox's Memory Unit: a card in a controller again, in the same two
	# sockets, so the pad saves which slot holds it exactly as it does a VMU.
	"xbox_mu": XBOX_MU_SCENE,
	# Pose only, like the Rumble Pak: which slot it is in is saved on the
	# controller holding it, not here.
	"jump_pack": JUMP_PACK_SCENE,
	# Pose only: which bay a cell is in, and at what roll, is saved on the thing
	# whose bay it is (cell_slots).
	"battery_aa": BATTERY_AA_SCENE,
	"battery_aaa": BATTERY_AAA_SCENE,
	# Pose only, like the pack: which slot it is in is saved on the pad holding
	# it, not here.
	"dc_microphone": DC_MICROPHONE_SCENE,
	# A pose here; which card slot its plug is in is applied by _apply_references.
	"gc_microphone": GC_MICROPHONE_SCENE,
	# A pose here; which controller socket it is in is applied by
	# _apply_references, and its microphone rides the cord.
	"n64_vru": N64_VRU_SCENE,
	# The bar's own entry is a pose; which console it is plugged into is applied
	# afterwards by _apply_references, like the remote's pairing.
	"sensor_bar": SENSOR_BAR_SCENE,
	# Instantiate-and-place here, with the volume and the two cabinet poses applied
	# afterwards by _restore_entry — the same split the sensor bar above uses. A
	# save row and a restore branch both existed for the pair, but nothing
	# ever built one back: a saved room dropped its speakers with "unknown object
	# type 'speaker_pair'", which also left any lead plugged into them with nothing
	# to seat into.
	"speaker_pair": SPEAKER_PAIR_SCENE,
}


## Which room's slots this instance reads and writes. Defaults to the arcade so
## that the callers which only serialize — netplay's object sync, the probes —
## need not name a room at all.
var room_id := DEFAULT_ROOM


func _init(room: String = DEFAULT_ROOM) -> void:
	if not room.is_empty():
		room_id = room


# ── Multi-slot public API ──────────────────────────────────────────────────────

## Returns ordered slot list. "clean" is always first and is never stored in the
## manifest — it is prepended here.
func get_slots() -> Array[Dictionary]:
	var m := _load_manifest()
	var result: Array[Dictionary] = [{"id": "clean", "name": "Clean Room", "readonly": true}]
	for s: Variant in m.get("slots", []):
		result.append(s as Dictionary)
	return result


## Save current scene state to the named slot. Returns false on I/O error.
func save_slot(root: Node, slot_id: String) -> bool:
	if slot_id == "clean":
		return false
	DirAccess.make_dir_recursive_absolute(slot_dir())
	return _write_scene_to_file(root, _slot_file(slot_id))


## Save without the frame hitch, for the periodic autosave.
##
## Profiled over a 27-object arcade: the walk is 0.46 ms but encoding and writing
## are 4.6 ms, and the write alone swings to 7 ms — half a frame at 90 Hz, gone.
## Only the walk has to see the live tree, so it stays here and the rest goes to a
## worker. Returns false if nothing was dispatched (unchanged, or a bad slot).
##
## An idle room re-encodes to the identical 17 KB every interval, so an unchanged
## payload is dropped rather than written: the point of the interval is to catch
## changes, not to keep rewriting a room nobody touched.
func autosave_slot(root: Node, slot_id: String) -> bool:
	if slot_id == "clean":
		return false
	var path := _slot_file(slot_id)
	var text := _encode(_snapshot(root))
	var digest := text.sha256_text()
	if _last_digest.get(path, "") == digest and FileAccess.file_exists(path):
		return false
	DirAccess.make_dir_recursive_absolute(slot_dir())
	_last_digest[path] = digest
	_dispatch_write(path, text)
	return true


# ── Deferred writes ───────────────────────────────────────────────────────────
#
# Statics, not instance state: callers build a ScenePersistence, save through it
# and drop it on the same line (see SceneManager._begin_transition), so an
# in-flight task outlives the object that started it.

## slot path -> sha256 of the payload last written there.
static var _last_digest: Dictionary = {}
## slot path -> WorkerThreadPool task id currently writing it.
static var _pending: Dictionary = {}


func _dispatch_write(path: String, text: String) -> void:
	# One writer per path. Waiting on the previous task is near-free in practice
	# (it has a whole interval's head start) and it is what stops two workers
	# interleaving store_string into the same file.
	_await_path(path)
	_pending[path] = WorkerThreadPool.add_task(
		func() -> void: _store_text(path, text), false, "scene autosave")


static func _await_path(path: String) -> void:
	if not _pending.has(path):
		return
	WorkerThreadPool.wait_for_task_completion(_pending[path])
	_pending.erase(path)


## Block until every deferred write has landed. Must be called before the app
## exits and before a slot file is read back, or a restore can race a half-written
## file. Cheap when nothing is outstanding.
static func flush_pending_writes() -> void:
	for path: Variant in _pending.keys():
		WorkerThreadPool.wait_for_task_completion(_pending[path])
	_pending.clear()


## Clear the scene then restore from the slot file, spread over frames — see
## instantiate_objects_async(). Loading "clean" just clears the scene.
##
## A coroutine: callers must await it, or they get a Signal back and the room
## fills in behind them.
func load_slot_async(root: Node, slot_id: String) -> bool:
	if slot_id == "clean":
		clear_scene(root)
		return true
	var path := _slot_file(slot_id)
	if not FileAccess.file_exists(path):
		push_warning("[ScenePersistence] slot file not found '%s'" % path)
		return false
	var objects: Variant = _read_objects(path)
	if objects == null:
		return false
	# Do not dismantle the room until the replacement has passed every check we
	# can perform without instantiating it. A truncated or old slot must be a
	# failed load, not an implicit "Clean Room" action.
	clear_scene(root)
	# Before the objects: the room's own furniture is what everything else was
	# arranged around, and a lead restored into a television still standing in its
	# authored place would be laid out to the wrong end of the room.
	_restore_fixtures(root, _read_fixtures(path))
	_restore_switches(root, _read_switches(path))
	var spawned: Dictionary = await instantiate_objects_async(root, objects)
	print("[ScenePersistence] loaded %d objects from '%s'" % [spawned.size(), path])
	return true


# ── The carry ─────────────────────────────────────────────────────────────────
#
# The room exactly as it stands, written for ONE restore to bring back in place of
# its active slot: SceneManager.carry_room, before a reload or a restart that the
# player did not ask to leave the room for. A file beside the slots, in no
# manifest, so the slot grid never lists it; the id cannot be a real slot's,
# which are eight hex digits.

const CARRY_SLOT := "_carry"


## Synchronous, because the next thing may be the process exiting.
func save_carry(root: Node) -> bool:
	DirAccess.make_dir_recursive_absolute(slot_dir())
	return _write_scene_to_file(root, _slot_file(CARRY_SLOT))


## Restore the carry, then delete it whether or not it loaded: it is good for one
## restore, and a failed one falls back to the slot.
func load_carry_async(root: Node) -> bool:
	var ok: bool = await load_slot_async(root, CARRY_SLOT)
	discard_carry()
	return ok


func discard_carry() -> void:
	var path := _slot_file(CARRY_SLOT)
	_await_path(path)
	_last_digest.erase(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Remove a slot from the manifest and delete its file.
func delete_slot(slot_id: String) -> bool:
	if slot_id == "clean":
		return false
	var m := _load_manifest()
	var new_slots: Array = []
	for s: Variant in m.get("slots", []):
		if (s as Dictionary).get("id", "") != slot_id:
			new_slots.append(s)
	m["slots"] = new_slots
	_save_manifest(m)
	var path := _slot_file(slot_id)
	# A worker still holding this path would recreate the file behind the delete.
	_await_path(path)
	_last_digest.erase(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var picture := thumbnail_path(slot_id)
	if FileAccess.file_exists(picture):
		DirAccess.remove_absolute(picture)
	return true


## Rename a slot in the manifest.
func rename_slot(slot_id: String, new_name: String) -> bool:
	if slot_id == "clean":
		return false
	var m := _load_manifest()
	var slots: Array = m.get("slots", [])
	for s: Variant in slots:
		var slot := s as Dictionary
		if slot.get("id", "") == slot_id:
			slot["name"] = new_name
			m["slots"] = slots
			return _save_manifest(m)
	return false


## Save current scene to a brand-new slot and append it to the manifest.
## Returns the new slot id.
func create_new_slot(root: Node, name: String) -> String:
	DirAccess.make_dir_recursive_absolute(slot_dir())
	var slot_id := _generate_id()
	_write_scene_to_file(root, _slot_file(slot_id))
	var m := _load_manifest()
	var slots: Array = m.get("slots", [])
	slots.append({"id": slot_id, "name": name})
	m["slots"] = slots
	_save_manifest(m)
	return slot_id


## Free all dynamically-spawned objects.
func clear_scene(root: Node) -> void:
	var spawned := root.get_tree().get_nodes_in_group("spawned")

	# Pre-pass: drop cable/controller plugs while their snap-zones are still alive.
	# Cable instances are in "spawned".  Their plug child may be snapped into a
	# snap-zone.  Calling drop() clears _grab_driver before queue_free.
	for node: Node in spawned:
		# The captive A/V lead ends in three connectors, not one — the picture cord
		# plus the audio pair beside it — and any of them can be sitting in a socket.
		# A mains lead's two ends are named for which is which, and either can be in
		# one: the wall end in an outlet, the appliance end in a machine's inlet.
		for plug_name: String in ["CablePlug", "CablePlugL", "CablePlugR", "ControllerPlug",
				"WallPlug", "AppliancePlug"]:
			var plug := node.get_node_or_null(plug_name)
			if plug and plug.has_method("drop"):
				plug.call("drop")

	# Main pass: power off and free everything. Instantly: a room teardown is not
	# a player deleting one object, and a shrink here would leave this room's
	# nodes alive while the next room loads over them.
	Vanish.instant = true
	for node: Node in spawned:
		# Power off systems so the emulation thread shuts down cleanly.
		#
		# power_off(), not toggle_power(): the toggle is the POWER BUTTON's verb and
		# it answers to the session. In netplay it stops the lockstep game, or sends
		# the intent to the host, and returns in both cases WITHOUT stopping the core
		# in front of it — so tearing a room down mid-session made a network call and
		# then freed a machine that was still running. power_off is the local,
		# unconditional stop, which is the only thing a teardown ever means.
		if node is RetroSystem and (node as RetroSystem).is_powered_on:
			(node as RetroSystem).power_off()
		# drop_and_free() clears _grab_driver before queue_free, preventing a
		# use-after-free in XRToolsPickable._exit_tree when a snap-zone that
		# was "holding" this pickable gets freed first.
		if node.has_method("drop_and_free"):
			node.call("drop_and_free")
		else:
			node.queue_free()
	Vanish.instant = false


# ── Private helpers ────────────────────────────────────────────────────────────

## Where this room's slots live. The folder is the room id URI-encoded, because a
## mod's room is "<mod>:<name>" and Windows refuses a ':' in a folder name: the
## first save in a mod room failed to create the folder (ERR_CANT_CREATE) and the
## manifest after it. Every shipped id is plain [a-z] and encodes to itself, so
## their folders do not move; uri_decode() gives the id back.
func slot_dir() -> String:
	return "%s/%s" % [ROOMS_DIR, room_id.uri_encode()]


func _manifest_file() -> String:
	return slot_dir() + "/manifest.json"


func _slot_file(slot_id: String) -> String:
	return slot_dir() + "/" + slot_id + ".json"


## The slot's picture for the SCENE tab (SceneThumbnail), beside its file.
func thumbnail_path(slot_id: String) -> String:
	return slot_dir() + "/" + slot_id + ".png"


func _generate_id() -> String:
	return "%08x" % (randi() ^ Time.get_ticks_msec())


func _empty_manifest() -> Dictionary:
	return {"version": VERSION, "slots": []}


## The slot index, or an empty one.
##
## A file that is ABSENT and a file that is present but unreadable both end up
## as an empty manifest, because there is nothing better to return — but they
## are not the same event and the second one is loud. A corrupt index means the
## player's slots are still on disk while the room reports none, and the next
## CRUD operation writes the empty manifest back over it, turning a bad read
## into permanent loss. Saying so is what gives anyone a chance to notice
## before that second step.
func _load_manifest() -> Dictionary:
	var path := _manifest_file()
	if not FileAccess.file_exists(path):
		return _empty_manifest()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[ScenePersistence] cannot read slot manifest '%s' (error %d) — "
			% [path, FileAccess.get_open_error()]
			+ "the room will report no saves although its slots are still on disk")
		return _empty_manifest()
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	push_error("[ScenePersistence] slot manifest '%s' is not readable JSON — " % path
		+ "the room will report no saves although its slots are still on disk")
	return _empty_manifest()


## Through JsonStore, like every other player-facing store, rather than opening
## the real file and writing into it.
##
## This one is the slot INDEX for a room: lose it and the player's saves are
## still on disk but no longer listed. Writing in place meant a crash or a power
## cut between open and store_string left a truncated file, and truncated JSON
## does not parse, so the room would come back with no slots at all. JsonStore
## stages a .part and renames it, so the manifest is either the old one or the
## new one.
func _save_manifest(manifest: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(slot_dir())
	return JsonStore.write_dict(_manifest_file(), manifest, "ScenePersistence")


func _write_scene_to_file(root: Node, path: String) -> bool:
	var snapshot := _snapshot(root)
	var objects: Array = snapshot["objects"]
	var text := _encode(snapshot)
	# An autosave of this same slot may still be in a worker; letting it land after
	# an explicit save would undo it.
	_await_path(path)
	if not _store_text(path, text):
		return false
	_last_digest[path] = text.sha256_text()
	print("[ScenePersistence] saved %d objects to '%s'" % [objects.size(), path])
	return true


## Walk the spawned set and serialize it. Main thread only: every entry reads live
## node state (global transforms, a TV's CRT params, a cable's seating).
func _collect_objects(root: Node) -> Array[Dictionary]:
	var nodes := root.get_tree().get_nodes_in_group("spawned")
	# The whole map has to exist before anything serializes: a reference can point
	# either way through the set.
	var node_to_id: Dictionary = {}
	for i in range(nodes.size()):
		node_to_id[nodes[i]] = i
	var objects: Array[Dictionary] = []
	for i in range(nodes.size()):
		var data := serialize_node(nodes[i], i, node_to_id)
		if not data.is_empty():
			objects.append(data)
	return objects


## Everything a slot file holds, ready to encode.
func _snapshot(root: Node) -> Dictionary:
	var out := {"version": VERSION, "objects": _collect_objects(root)}
	var fixtures := _collect_fixtures(root)
	# Omitted entirely when the room has none, so a room without fixtures writes
	# the same bytes it always did.
	if not fixtures.is_empty():
		out["fixtures"] = fixtures
	var switches := _collect_switches(root)
	if not switches.is_empty():
		out["switches"] = switches
	return out


## Authored objects the player can move.
##
## The arcade's television is instanced by the room rather than spawned into it,
## so it is not in the "spawned" group and the object walk never sees it — but it
## is an XRToolsPickable and can be carried anywhere, and its position was simply
## lost. It cannot join "spawned" to fix that: clear_scene frees that whole group,
## and a slot load would delete the room's own television with nothing in the file
## to rebuild it.
##
## So fixtures are recorded separately and by PATH, and restoring one moves the
## node that is already there. Membership comes from the room's .tscn
## (groups=["fixture"]), which is what keeps a spawned television — same scene,
## no group — out of this list.
func _collect_fixtures(root: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if root.get_tree() == null:
		return out
	for node: Node in root.get_tree().get_nodes_in_group("fixture"):
		var n3d := node as Node3D
		if n3d == null or not root.is_ancestor_of(n3d):
			continue
		var pos := n3d.global_position
		var rot := n3d.global_rotation_degrees
		var record := {
			"path": str(root.get_path_to(n3d)),
			"position": [pos.x, pos.y, pos.z],
			"rotation": [rot.x, rot.y, rot.z],
		}
		# The set's selected input. A spawned television carries its whole control
		# state in its object entry; a fixture has no entry to carry one, so the
		# arcade's own set came back on Composite 1 however it was left.
		if n3d is RetroTV:
			record["source"] = (n3d as RetroTV).current_source
		out.append(record)
	return out


## Put the room's own movable furniture back where it was left. Absent from every
## slot written before fixtures existed, in which case the room keeps the pose its
## .tscn authored.
func _restore_fixtures(root: Node, fixtures: Variant) -> void:
	if not fixtures is Array:
		return
	for entry: Variant in fixtures as Array:
		if not entry is Dictionary:
			continue
		var rec := entry as Dictionary
		var n3d := root.get_node_or_null(NodePath(str(rec.get("path", "")))) as Node3D
		if n3d == null:
			# A room whose furniture was renamed or removed since the save.
			continue
		var pos: Array = rec.get("position", [])
		var rot: Array = rec.get("rotation", [])
		if pos.size() == 3:
			n3d.global_position = Vector3(pos[0], pos[1], pos[2])
		if rot.size() == 3:
			n3d.global_rotation_degrees = Vector3(rot[0], rot[1], rot[2])
		# Absent from a slot written before a set remembered its input, and from
		# every fixture that is furniture rather than a television. set_source
		# clamps and falls back on its own, so a cabinet that no longer carries
		# the saved input lands on one it does have.
		var source: Variant = rec.get("source")
		if n3d is RetroTV and (source is float or source is int):
			(n3d as RetroTV).set_source(int(source))


## The room's wall switches, keyed by node path the same way object_sync keys them
## for a late joiner. A switch is not a fixture: it never moves, and what has to
## survive a save is which way its bat is thrown and whether the lights it drives
## are on. Omitted for a room with no switches, so those slots write the bytes
## they always did.
func _collect_switches(root: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node: Node in root.find_children("*", "LightSwitch", true, false):
		out.append({
			"path": str(root.get_path_to(node)),
			"on": bool((node as LightSwitch).lights_on),
		})
	return out


## Absent from every slot written before switches were recorded, in which case the
## room keeps the lit state its .tscn authored.
func _restore_switches(root: Node, switches: Variant) -> void:
	if not switches is Array:
		return
	for entry: Variant in switches as Array:
		if not entry is Dictionary:
			continue
		var rec := entry as Dictionary
		var sw := root.get_node_or_null(NodePath(str(rec.get("path", "")))) as LightSwitch
		if sw == null:
			# A room whose switch plate was renamed or removed since the save.
			continue
		sw.set_lights_on(bool(rec.get("on", true)))


func _encode(snapshot: Dictionary) -> String:
	return JSON.stringify(snapshot, "\t")


## Through JsonStore's staged write, for the same reason _save_manifest is: this
## one writes the SLOT — the room, every object in it and where each one stood.
## Writing in place meant a crash or a power cut between the open and the store
## left a truncated file, and truncated JSON does not parse, so the save was not
## stale but gone. The old version also returned true without ever asking
## whether the store had landed.
func _store_text(path: String, text: String) -> bool:
	return JsonStore.write_text(path, text, "ScenePersistence")


## The fixture entries of a slot file — an empty array for one written before
## fixtures existed, for a room that has none, or for a file that cannot be read
## (silently: _read_objects has already said so about the same file).
func _read_fixtures(path: String) -> Variant:
	_await_path(path)
	return JsonStore.read_dict(path).get("fixtures", [])


## The switch entries of a slot file - an empty array for one written before
## switches were recorded, for a room that has none, or for an unreadable file.
func _read_switches(path: String) -> Variant:
	_await_path(path)
	return JsonStore.read_dict(path).get("switches", [])


## The object entries of a slot file, or null if it cannot be read.
func _read_objects(path: String) -> Variant:
	# Never read a file a worker is still writing — a truncated slot parses as an
	# invalid file and restores as an empty room.
	_await_path(path)
	# No owner, so JsonStore says nothing and the error below is the one line. A
	# missing slot is null in silence, as it always was; one that exists but does
	# not parse, or is not an object (JsonStore's {}: a slot always has a version,
	# so an empty object is no slot either), is an invalid file.
	var parsed: Variant = JsonStore.parse_dict(path)
	if parsed == null and not FileAccess.file_exists(path):
		return null
	if parsed == null or (parsed as Dictionary).is_empty():
		push_error("[ScenePersistence] invalid slot file '%s'" % path)
		return null
	var doc := parsed as Dictionary
	# Refused rather than migrated. Every cross-reference changed shape in v2, so
	# a v1 file still restores its objects — into a room where nothing is plugged
	# into anything, which reads as a bug rather than as an old save.
	var file_version := int(doc.get("version", 1))
	if file_version != VERSION:
		push_warning("[ScenePersistence] slot '%s' is version %d, this build reads %d"
			% [path, file_version, VERSION])
		return null
	var objects: Variant = doc.get("objects", [])
	if not objects is Array:
		push_error("[ScenePersistence] slot '%s' has no object list" % path)
		return null
	# Entries naming a type this build no longer has are DROPPED, not fatal.
	#
	# This used to refuse the whole file on the first unknown type, which meant
	# deleting a mod that contributed one prop made every slot containing one
	# unreadable — the player lost the room, not the prop. That was also flatly
	# inconsistent with the rest of the system: a console whose model_id has gone
	# falls back through SystemModelRegistry.resolve(), and a controller whose
	# scene has gone falls back to the generic pad. Both degrade; only this did
	# not.
	#
	# Structural corruption is still all-or-nothing below. A truncated file
	# restoring as an empty room is a deliberate guard, and nothing here weakens
	# it: only an unrecognised `type` is survivable.
	var pruned := _prune_unknown_types(objects as Array, path)
	var error := _objects_validation_error(pruned)
	if not error.is_empty():
		push_error("[ScenePersistence] invalid slot '%s': %s" % [path, error])
		return null
	return pruned


## Is this a type this build can build? Mod props count, while their mod is
## loaded — which is exactly why a slot must survive one of them going away.
static func _is_known_type(obj_type: String) -> bool:
	return PLAIN_SCENES.has(obj_type) or _LOAD_KINDS.has(obj_type) \
		or _mod_objects.has(obj_type)


## Drop entries naming a type this build does not have, and scrub every
## reference that pointed at one.
##
## The scrub is not optional and the ORDER is not arbitrary. Dropping an entry
## creates dangling ids in whatever referenced it — a console's `tv`, a card's
## `system` — and _reference_validation_error rejects a dangling id, so pruning
## without scrubbing would turn "one missing prop" back into "the whole slot is
## invalid", which is the bug this exists to fix.
##
## A reference is cleared to null rather than remapped: null is already the
## "not connected to anything" value every restore path handles, because that is
## what an object saved unplugged looks like.
static func _prune_unknown_types(objects: Array, path: String) -> Array:
	var dropped_ids: Dictionary = {}
	var kept: Array = []
	var dropped_types: Dictionary = {}
	for value: Variant in objects:
		if not (value is Dictionary):
			kept.append(value)          # let the validator below complain
			continue
		var entry := value as Dictionary
		var obj_type := str(entry.get("type", ""))
		if not obj_type.is_empty() and not _is_known_type(obj_type):
			if entry.get("id") != null:
				dropped_ids[int(entry["id"])] = true
			dropped_types[obj_type] = int(dropped_types.get(obj_type, 0)) + 1
			continue
		kept.append(entry)
	# Keyed on what was DROPPED, not on the ids of what was dropped. An unknown
	# entry carries an id only if the save recorded one, so an id-less entry used
	# to leave dropped_ids empty, take this early return, and be handed back in
	# `objects` — re-admitting the exact row the pruning had just removed. The
	# validator then rejected it and failed the whole slot, which is the outcome
	# this function exists to prevent.
	if dropped_types.is_empty():
		return objects
	for value: Variant in kept:
		if not (value is Dictionary):
			continue
		var entry := value as Dictionary
		for field: String in _REFERENCE_FIELDS:
			if not entry.has(field):
				continue
			var ref: Variant = entry[field]
			if _is_integer(ref) and dropped_ids.has(int(ref)):
				entry[field] = null
		for cover_field: String in ["port_covers", "cover_slots"]:
			var covers: Variant = entry.get(cover_field)
			if covers is Dictionary:
				for socket: Variant in (covers as Dictionary):
					var cover_ref: Variant = (covers as Dictionary)[socket]
					if _is_integer(cover_ref) and dropped_ids.has(int(cover_ref)):
						(covers as Dictionary)[socket] = null
		# A dropped mod's cell leaves its battery seat empty.
		var cell_slots: Variant = entry.get("cell_slots")
		if cell_slots is Dictionary:
			for seat: Variant in (cell_slots as Dictionary).keys():
				var one: Variant = (cell_slots as Dictionary)[seat]
				var cell_ref: Variant = (one as Dictionary).get("cell") if one is Dictionary else null
				if _is_integer(cell_ref) and dropped_ids.has(int(cell_ref)):
					(cell_slots as Dictionary).erase(seat)
		# A dropped mod's pad in a multitap socket leaves the socket empty.
		var sockets: Variant = entry.get("sockets")
		if sockets is Array:
			for i in (sockets as Array).size():
				var socket_ref: Variant = (sockets as Array)[i]
				if _is_integer(socket_ref) and dropped_ids.has(int(socket_ref)):
					(sockets as Array)[i] = null
		# A prop sitting in a dropped mod's object is simply loose.
		var attached: Variant = entry.get("attached")
		if attached is Dictionary:
			var to: Variant = (attached as Dictionary).get("to")
			if _is_integer(to) and dropped_ids.has(int(to)):
				entry.erase("attached")
	var summary := PackedStringArray()
	var dropped_count := 0
	for obj_type: String in dropped_types:
		summary.append("%d %s" % [dropped_types[obj_type], obj_type])
		dropped_count += int(dropped_types[obj_type])
	# push_warning rather than push_error: the slot loaded, and the player is
	# about to see the room. This is a report, not a failure.
	push_warning("[ScenePersistence] slot '%s' skipped %s — the mod that provided %s is not loaded"
		% [path, ", ".join(summary), "them" if dropped_count > 1 else "it"])
	return kept


static func _objects_validation_error(objects: Array) -> String:
	var ids: Dictionary = {}
	for index in objects.size():
		var value: Variant = objects[index]
		if not value is Dictionary:
			return "object %d is not a dictionary" % index
		var entry := value as Dictionary
		var id_value: Variant = entry.get("id")
		if not _is_integer(id_value) or int(id_value) < 0:
			return "object %d has an invalid id" % index
		var id := int(id_value)
		if ids.has(id):
			return "object %d repeats id %d" % [index, id]
		ids[id] = true

	for index in objects.size():
		var entry := objects[index] as Dictionary
		var error := _entry_validation_error(entry, ids)
		if not error.is_empty():
			return "object %d: %s" % [index, error]
	return ""


static func _entry_validation_error(entry: Dictionary, ids: Dictionary) -> String:
	var obj_type_value: Variant = entry.get("type")
	if not obj_type_value is String:
		return "type is not a string"
	var obj_type := obj_type_value as String
	if not _is_known_type(obj_type):
		return "unknown type '%s'" % obj_type
	for field: String in ["position", "rotation"]:
		var pose_error := _vec3_validation_error(entry.get(field))
		if not pose_error.is_empty():
			return "%s %s" % [field, pose_error]
	for field: String in _STRING_FIELDS:
		if entry.has(field) and not entry[field] is String:
			return "%s is not a string" % field
	for field: String in _NUMBER_FIELDS:
		if entry.has(field) and not _is_finite_number(entry[field]):
			return "%s is not a finite number" % field
	for field: String in _BOOL_FIELDS:
		if entry.has(field) and not entry[field] is bool:
			return "%s is not a boolean" % field
	for field: String in _REFERENCE_FIELDS:
		if entry.has(field):
			var ref_error := _reference_validation_error(entry[field], ids)
			if not ref_error.is_empty():
				return "%s %s" % [field, ref_error]

	if entry.has("expansions"):
		if not entry["expansions"] is Array:
			return "expansions is not an array"
		for ref: Variant in entry["expansions"]:
			var ref_error := _reference_validation_error(ref, ids)
			if not ref_error.is_empty():
				return "expansions member %s" % ref_error
	for cover_field: String in ["port_covers", "cover_slots"]:
		if not entry.has(cover_field):
			continue
		if not entry[cover_field] is Dictionary:
			return "%s is not a dictionary" % cover_field
		for socket: Variant in entry[cover_field]:
			var ref_error := _reference_validation_error(entry[cover_field][socket], ids)
			if not ref_error.is_empty():
				return "%s %s %s" % [cover_field, socket, ref_error]
	if entry.has("cell_slots"):
		if not entry["cell_slots"] is Dictionary:
			return "cell_slots is not a dictionary"
		for seat: Variant in entry["cell_slots"]:
			var one: Variant = entry["cell_slots"][seat]
			if not one is Dictionary:
				return "cell_slots %s is not a dictionary" % seat
			var ref_error := _reference_validation_error((one as Dictionary).get("cell"), ids)
			if not ref_error.is_empty():
				return "cell_slots %s %s" % [seat, ref_error]
			if (one as Dictionary).has("roll") and not _is_finite_number((one as Dictionary)["roll"]):
				return "cell_slots %s roll is not a finite number" % seat
	if entry.has("cover_size"):
		var size_error := _vec3_validation_error(entry["cover_size"])
		if not size_error.is_empty():
			return "cover_size %s" % size_error
	if entry.has("cover_socket") and not entry["cover_socket"] is String:
		return "cover_socket is not a string"
	if entry.has("extra_tvs"):
		if not entry["extra_tvs"] is Array:
			return "extra_tvs is not an array"
		for ref: Variant in entry["extra_tvs"]:
			var ref_error := _reference_validation_error(ref, ids)
			if not ref_error.is_empty():
				return "extra_tvs member %s" % ref_error
	if entry.has("sockets"):
		if not entry["sockets"] is Array:
			return "sockets is not an array"
		for ref: Variant in entry["sockets"]:
			var ref_error := _reference_validation_error(ref, ids)
			if not ref_error.is_empty():
				return "sockets member %s" % ref_error
	if entry.has("tv_inputs"):
		if not entry["tv_inputs"] is Array:
			return "tv_inputs is not an array"
		for input: Variant in entry["tv_inputs"]:
			if not _is_integer(input):
				return "tv_inputs contains a non-integer"
	if entry.has("crt_params"):
		if not entry["crt_params"] is Dictionary:
			return "crt_params is not a dictionary"
		for key: Variant in (entry["crt_params"] as Dictionary):
			if not key is String or not _is_finite_number(entry["crt_params"][key]):
				return "crt_params contains a non-numeric value"
	if entry.has("controls"):
		if not entry["controls"] is Dictionary:
			return "controls is not a dictionary"
		var controls := entry["controls"] as Dictionary
		for field: String in ["enabled", "muted", "widescreen"]:
			if controls.has(field) and not controls[field] is bool:
				return "controls.%s is not a boolean" % field
		if controls.has("volume") and not _is_finite_number(controls["volume"]):
			return "controls.volume is not a finite number"
		for field: String in ["source", "rf_channel", "channel_index",
				"audio_mode", "audio_out"]:
			if controls.has(field) and not _is_integer(controls[field]):
				return "controls.%s is not an integer" % field
	if entry.has("boxes"):
		var boxes_error := _pose_records_validation_error(entry["boxes"], ids, false)
		if not boxes_error.is_empty():
			return "boxes %s" % boxes_error
	if entry.has("plugs"):
		var plugs_error := _pose_records_validation_error(entry["plugs"], ids, true)
		if not plugs_error.is_empty():
			return "plugs %s" % plugs_error
	if entry.has("attached"):
		if not entry["attached"] is Dictionary:
			return "attached is not a dictionary"
		var attached := entry["attached"] as Dictionary
		var ref_error := _reference_validation_error(attached.get("to"), ids)
		if not ref_error.is_empty():
			return "attached.to %s" % ref_error
		if not attached.get("zone") is String:
			return "attached.zone is not a string"
	if entry.has("body"):
		if not entry["body"] is Dictionary:
			return "body is not a dictionary"
		for field: String in ["position", "rotation"]:
			var pose_error := _vec3_validation_error((entry["body"] as Dictionary).get(field))
			if not pose_error.is_empty():
				return "body %s %s" % [field, pose_error]
	return ""


static func _pose_records_validation_error(value: Variant, ids: Dictionary,
		validate_plug: bool) -> String:
	if not value is Array:
		return "is not an array"
	for index in (value as Array).size():
		var record_value: Variant = (value as Array)[index]
		if not record_value is Dictionary:
			return "member %d is not a dictionary" % index
		var record := record_value as Dictionary
		for field: String in ["position", "rotation"]:
			var pose_error := _vec3_validation_error(record.get(field))
			if not pose_error.is_empty():
				return "member %d %s %s" % [index, field, pose_error]
		if not validate_plug:
			continue
		for field: String in ["end", "cord"]:
			if not _is_integer(record.get(field)):
				return "member %d %s is not an integer" % [index, field]
		if record.has("port") and not record["port"] is String:
			return "member %d port is not a string" % index
		if record.has("device"):
			var ref_error := _reference_validation_error(record["device"], ids)
			if not ref_error.is_empty():
				return "member %d device %s" % [index, ref_error]
	return ""


static func _vec3_validation_error(value: Variant) -> String:
	if not value is Array or (value as Array).size() != 3:
		return "is not a three-component array"
	for component: Variant in value:
		if not _is_finite_number(component):
			return "contains a non-finite number"
	return ""


static func _reference_validation_error(value: Variant, ids: Dictionary) -> String:
	if value == null or value is String:
		return ""
	if not _is_integer(value) or int(value) < 0:
		return "is not a reference"
	return "" if ids.has(int(value)) else "references missing id %d" % int(value)


static func _is_integer(value: Variant) -> bool:
	return _is_finite_number(value) and float(value) == floorf(float(value))


static func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


# ── Cross-references ───────────────────────────────────────────────────────────
#
# One object pointing at another is the only thing in a slot file that isn't a
# plain value, and it comes in two flavours: a peer inside this save, and a
# fixture standing in the room that the save doesn't own. Both encode to a single
# JSON value — an int id for the peer, a scene path for the fixture, null for
# nothing — so every site that records or resolves a reference uses this pair
# rather than its own _id/_path key couple.

## Encode a reference to target. Returns int, String or null.
func _ref(node_to_id: Dictionary, target: Node) -> Variant:
	if target == null:
		return null
	if node_to_id.has(target):
		return node_to_id[target]
	# Not in the map. A scene-placed fixture has no id and never will, so name it
	# by path. A "spawned" node missing from the map means a partial serialize
	# (ObjectSync ships one object at a time) — its path is a dynamic name that
	# means nothing to the peer receiving it, so drop the reference instead.
	if target.is_in_group("spawned"):
		return null
	return str(target.get_path())


## Resolve what _ref() wrote. Null when the reference was empty or has gone.
func _resolve_ref(root: Node, spawned: Dictionary, ref: Variant) -> Node:
	if ref == null:
		return null
	if ref is String:
		var node := root.get_node_or_null(ref as String)
		if node == null:
			push_warning("[ScenePersistence] no node at '%s'" % ref)
		return node
	# JSON has no integer type, so an id parses back as a float.
	return spawned.get(int(ref)) as Node


## Instantiate serialized object entries under root and restore their
## cross-connections (two passes). Returns {id: Node3D} for the spawned set.
## Shared by slot loading and multiplayer world snapshots (ObjectSync).
func instantiate_objects(root: Node, objects: Array) -> Dictionary:
	var spawned: Dictionary = {}
	var entries: Dictionary = {}
	var held: Dictionary = {}
	for entry: Variant in objects:
		_spawn_entry(root, entry, spawned, entries, held)
	_hold_still_group(root, held)
	_restore_connections(root, spawned, entries)
	_let_go(held)
	return spawned


## Same, but hands a frame back once it has held the main thread for
## FRAME_BUDGET_USEC. A slot restored as part of a room change is built at the
## exact moment the headset has nothing new to draw: a save with a dozen systems
## in it blocks for a second, and a blocked main thread in VR is a frozen image,
## not a slow one. Callers that need every object within the frame — netplay
## snapshots — use instantiate_objects(), which stays a plain function because a
## body containing await would hand them a Signal instead of the spawned set.
func instantiate_objects_async(root: Node, objects: Array) -> Dictionary:
	var spawned: Dictionary = {}
	var entries: Dictionary = {}
	var tree := root.get_tree()
	var held: Dictionary = {}
	_restore_generation += 1
	var generation := _restore_generation
	var deadline := Time.get_ticks_usec() + FRAME_BUDGET_USEC
	var total := objects.size()
	var done := 0
	restore_progress.emit(0, total)
	for entry: Variant in objects:
		# A saved bespoke console names a GLB that may still be warming at boot.
		# Spawning it now would load() that GLB synchronously inside _ready —
		# measured 6.9 s of frozen frame for the NES on a Quest 3. Await it into
		# the cache instead; once warm this never suspends.
		await _acquire_entry_assets(entry)
		if not _still_ours(root, generation):
			_let_go(held)
			return spawned
		_spawn_entry(root, entry, spawned, entries, held)
		done += 1
		if Time.get_ticks_usec() < deadline:
			continue
		restore_progress.emit(done, total)
		await tree.process_frame
		if not _still_ours(root, generation):
			_let_go(held)
			return spawned
		deadline = Time.get_ticks_usec() + FRAME_BUDGET_USEC
	# The connection pass still has to seat every plug, so this is not "done" —
	# it is the last point where a count of objects means anything.
	restore_progress.emit(total, total)
	_hold_still_group(root, held)
	await _restore_connections_async(root, spawned, entries, generation)
	_let_go(held)
	return spawned


## No-op for everything but a system entry whose model carries external assets.
func _acquire_entry_assets(entry: Variant) -> void:
	if not entry is Dictionary:
		return
	var rec := entry as Dictionary
	match str(rec.get("type", "")):
		"system":
			var row := SystemModelRegistry.resolve(str(rec.get("model_id", "")),
				SystemIds.canonical(str(rec.get("systemid", ""))))
			for path: String in row.get("requires", []):
				await ModelWarmer.acquire(path)
		"cartridge":
			# Same story, a cartridge body: the fields as _apply_media_fields reads them.
			var cart_systemid := SystemIds.canonical(str(rec.get("cart_systemid", "")))
			var cart_rom := RomLibrary.relocate(str(rec.get("rom_path", "")))
			var pin := str(rec.get("fallback_market", ""))
			var body := RetroCartridge.body_model_for(cart_systemid, cart_rom,
				str(rec.get("body_region", "")), StringName(str(rec.get("shell_preset", ""))), pin)
			if not body.is_empty() and ResourceLoader.exists(body):
				await ModelWarmer.acquire(body)
			# And the PAL rear sticker a Super Famicom-shaped cartridge wears.
			var sticker := SnesCartShell.rear_sticker_file(body, cart_systemid, cart_rom, pin)
			if not sticker.is_empty():
				await ModelWarmer.acquire(sticker)


func _spawn_entry(root: Node, entry: Variant, spawned: Dictionary, entries: Dictionary,
		held: Dictionary) -> void:
	if not entry is Dictionary:
		return
	var rec := entry as Dictionary
	var id: int = rec.get("id", -1)
	if id < 0:
		return
	var obj := deserialize_object(rec)
	if obj == null:
		return
	# Before it enters the room, where a mod's hook builds its covers' slots: a
	# restored object's covers are the save's, not fresh ones (CoverSlots).
	obj.set_meta(CoverSlots.RESTORING, true)
	root.add_child(obj)
	obj.add_to_group("spawned")
	_hold_still(obj, held)
	# A lead's connectors are stood up here rather than with the rest of its wiring
	# in pass 2. Where they go needs nothing from the other objects, and the lead
	# lays its cord out around them at the end of THIS frame — so leaving them until
	# pass 2 hangs the cord in mid-air over the desk for as many frames as the
	# restore takes to reach it. Which socket holds which is still pass 2's, because
	# that genuinely does need every device to exist.
	if obj is CompositeCable or obj is PowerCord or obj is PowerStrip or obj is TravelAdapter:
		obj.call("restore_plug_poses", rec.get("plugs", []))
	spawned[id] = obj
	entries[id] = rec


## Take gravity off every rigid body in a freshly spawned object, remembering what
## it had. _let_go gives it back once the whole room is wired.
##
## Restoring is two passes — pass 1 stands the objects where they were left, pass 2
## hands each one to whatever was holding it — and both are budgeted to a few ms a
## frame so the headset keeps drawing (see instantiate_objects_async). Everything
## restored is an XRToolsPickable, which is a RigidBody3D, live from the moment it
## is added. So a cartridge saved in its slot spawns at the slot's pose with nothing
## under it and falls out; a disc in a tray does the same; anything resting on
## another restored object falls through the gap until that one arrives. Measured
## on a 24-object slot: one to three seconds of that before pass 2 catches up. The
## whole room appeared to rain into place.
##
## And touching nothing (collision_mask 0) until the restore hands it back. A unit
## seated in a console comes back at its seated pose, inside the console's slot,
## and until pass 2 seats it the two are not excepted from each other: Jolt pushed
## them apart, and the console went down into its table — as far as the 2 cm
## penetration slop lets a body sink, a little further each load. A Super Game
## Boy's SNES was 13.8 mm in after one load and 20 mm after two. The mask is free
## to borrow: XRToolsPickable keeps the one it read in _ready, which is what it
## hands back when it is let go of, and sets 0 itself while it is held.
##
## Gravity rather than `freeze`, deliberately. Three other things own that flag and
## would fight over it: XRToolsPickable snapshots it at pick-up and hands it back on
## release — so a cartridge seated in pass 2 while frozen would stay frozen in
## mid-air when the player pulled it out (the correction RetroTV._on_tv_grabbed has
## to make for its own park) — plus FloatLock parks with it and RetroSystem keeps its
## own copy of that. gravity_scale is written by no script in the project.
func _hold_still(node: Node, held: Dictionary) -> void:
	if node is RigidBody3D:
		var body := node as RigidBody3D
		var id := body.get_instance_id()
		# Keyed, and never overwritten: _hold_still_group sweeps again a pass later
		# and would otherwise record the zero this already wrote as what the body
		# arrived with, so _let_go would hand back no gravity at all.
		if not held.has(id):
			held[id] = {"body": body, "gravity": body.gravity_scale, "mask": body.collision_mask}
			body.gravity_scale = 0.0
			body.collision_mask = 0
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
	for child in node.get_children():
		_hold_still(child, held)


## The same, over everything in the "spawned" group.
##
## A second sweep, run once pass 1 is finished, because the captive leads are not
## children of the object that owns them: a system, a keyboard or a mouse builds its
## cable in _ready and parents it to the current scene a frame later (see
## RetroSystem._add_cables_to_scene), so it does not exist yet when its owner spawns
## and the walk above cannot reach it. Its plug is the most visible faller of the
## lot — it spawns beside the console's jack and drops to the desk before pass 2
## puts it in the socket.
func _hold_still_group(root: Node, held: Dictionary) -> void:
	if root.get_tree() == null:
		return
	for node: Node in root.get_tree().get_nodes_in_group("spawned"):
		_hold_still(node, held)


## Hand the room back to physics. Woken as well as un-weighted: a body that stood
## still for the length of the restore has gone to sleep, and a sleeping body does
## not notice it has weight again.
func _let_go(held: Dictionary) -> void:
	for id: Variant in held:
		var rec: Dictionary = held[id]
		# Untyped on purpose. Assigning a freed instance to a TYPED local throws on
		# the assignment, so `var body: RigidBody3D = ...` made the is_instance_valid
		# below unreachable — and the throw abandoned the loop, leaving every body
		# after the freed one weightless and asleep for good. Overlapping restores
		# produce exactly this: the newer one frees what the older one is holding.
		var body: Variant = rec["body"]
		if not is_instance_valid(body):
			continue
		var rb := body as RigidBody3D
		rb.gravity_scale = rec["gravity"]
		# Solid again — unless pass 2 seated it, and the zone holding it owns the
		# mask now (0, until it is taken out), or something else has set one.
		var seated := rb is XRToolsPickable and (rb as XRToolsPickable).is_picked_up()
		# The held bit alone is a rider's coupling (HeldObjectPhysics.watch_riders)
		# laid on the zero, not a mask: kept, and the body's own put back under it.
		var own := rb.collision_mask & ~HeldObjectPhysics.HELD_BIT
		if own == 0 and not seated:
			var mask := int(rec.get("mask", rb.collision_mask))
			if rb.collision_mask != 0:
				print("[ScenePersistence] %s: collision mask %d -> %d at let-go" % [rb.name, rb.collision_mask, mask | rb.collision_mask])
			rb.collision_mask = mask | rb.collision_mask
		rb.sleeping = false
	held.clear()


## Pass 2: wire the spawned objects to each other. Has to run after every object
## exists, because a connection can point either way through the set.
func _restore_connections(root: Node, spawned: Dictionary, entries: Dictionary) -> void:
	for id: int in spawned:
		_restore_entry(root, id, spawned, entries)
	for id: int in spawned:
		_restore_rope_layouts(spawned[id], entries[id])
	_report_restored(spawned)


## Same, yielding a frame whenever it has held the main thread too long.
func _restore_connections_async(root: Node, spawned: Dictionary, entries: Dictionary,
		generation: int) -> void:
	var tree := root.get_tree()
	var deadline := Time.get_ticks_usec() + FRAME_BUDGET_USEC
	for id: int in spawned:
		_restore_entry(root, id, spawned, entries)
		if Time.get_ticks_usec() < deadline:
			continue
		await tree.process_frame
		if not _still_ours(root, generation):
			return
		deadline = Time.get_ticks_usec() + FRAME_BUDGET_USEC
	for id: int in spawned:
		_restore_rope_layouts(spawned[id], entries[id])
		if Time.get_ticks_usec() < deadline:
			continue
		await tree.process_frame
		if not _still_ours(root, generation):
			return
		deadline = Time.get_ticks_usec() + FRAME_BUDGET_USEC
	_report_restored(spawned)


## Restore after pass 2 has seated every plug. The saved particles preserve the
## actual route round furniture; VerletRope validates topology immediately and
## validates the route against live collision geometry on its next physics tick.
##
## obj is Variant on purpose, like _still_ours' root. The async pass yields
## frames between the wiring pass and this one, so an object spawned earlier in
## this very restore may already be freed by the time we get here — and binding
## a freed instance to a Node-typed parameter throws at the call boundary,
## before is_instance_valid below ever runs.
func _restore_rope_layouts(obj: Variant, entry: Dictionary) -> void:
	if not is_instance_valid(obj):
		return
	var node := obj as Node
	for rec: Dictionary in entry.get("rope_layouts", []):
		var rope := node.get_node_or_null(NodePath(str(rec.get("path", "")))) as VerletRope
		if rope == null:
			continue
		var points := PackedVector3Array()
		for raw: Variant in rec.get("points", []):
			if not raw is Array or (raw as Array).size() < 3:
				points = PackedVector3Array()
				break
			var xyz := raw as Array
			points.append(Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2])))
		if not rope.restore_points(points):
			push_warning("[ScenePersistence] rejected rope layout at %s" % rec.get("path", ""))


## False once the room we are building into has gone, or once a newer restore
## has taken over — either way this run must not touch the scene again.
##
## root is Variant on purpose. Being handed a freed room is the whole reason this
## exists, and binding a freed object to a Node-typed parameter throws before the
## body can run — the same way assigning one to a typed local does.
func _still_ours(root: Variant, generation: int) -> bool:
	if generation != _restore_generation:
		return false
	return is_instance_valid(root) and (root as Node).is_inside_tree()


func _report_restored(spawned: Dictionary) -> void:
	# A cabinet left switched on comes on once its board is in; one whose board never came stays off.
	for id: int in spawned:
		if is_instance_valid(spawned[id]) and spawned[id] is RetroSystem:
			(spawned[id] as RetroSystem).finish_attract_restore()
	if spawned.size() > 0:
		print("[ScenePersistence] instantiated %d objects" % spawned.size())


## One entry of a saved "tv_inputs" list, or Composite 1 for a save that predates
## the key, a channel it does not reach, or a value from a future set with more
## inputs than this one has.
static func _tv_input(inputs: Array, channel: int) -> int:
	if channel < 0 or channel >= inputs.size():
		return 0
	return clampi(int(inputs[channel]), 0, RetroTV.COMPOSITE_INPUTS - 1)


func _restore_entry(root: Node, id: int, spawned: Dictionary, entries: Dictionary) -> void:
	# The async pass yields frames, so an object spawned earlier in this very run
	# may already have been freed by the time we come to wire it up.
	if not is_instance_valid(spawned[id]):
		return
	var obj: Node = spawned[id]
	var rec: Dictionary = entries[id]
	_restore_articulated_controls(obj, rec.get("articulated", rec.get("hinges", [])))
	_restore_attachment(root, obj, spawned, rec)
	_restore_cover_slots(root, obj, spawned, rec)
	_restore_cell_slots(root, obj, spawned, rec)

	for row: Array in _restore_kind_rows():
		if is_instance_of(obj, row[0]):
			call(row[1] as StringName, root, id, obj, spawned, rec)
			return


## The restore side of _save_kind_rows: [class, hook], walked top to bottom by
## _restore_entry, the FIRST row the object `is` running its hook -- the same
## precedence as the `elif obj is X` chain it replaced, which this keeps row for
## row. `is` matches every ancestor, so a subclass's row must come before its
## base's; the order below is the old chain's. A type with no row has nothing to
## wire up after the pose, its attachment and its slots (restored above the walk).
##
## Every hook takes (root, id, obj, spawned, d), the arguments _restore_entry has.
## Built on first use, for _save_kind_rows' reason: the rows hold class scripts.
static var _restore_kinds: Array = []

static func _restore_kind_rows() -> Array:
	if not _restore_kinds.is_empty():
		return _restore_kinds
	_restore_kinds = [
		[RetroSystem, &"_restore_system"],
		[ArcadeBayUnit, &"_restore_arcade_bay"],
		[RetroExpansion, &"_restore_expansion"],
		[TransferPak, &"_restore_transfer_pak"],
		[RetroTV, &"_restore_tv"],
		[VCRPlayer, &"_restore_vcr_player"],
		[DVDPlayer, &"_restore_dvd_player"],
		[RetroAudioPlayer, &"_restore_audio_player"],
		[SpeakerPair, &"_restore_speaker_pair"],
		[SurroundAmp, &"_restore_surround_amp"],
		[CompositeCable, &"_restore_lead"],
		[PowerCord, &"_restore_lead"],
		[PowerStrip, &"_restore_lead"],
		[TravelAdapter, &"_restore_lead"],
		[SpeakerStand, &"_restore_speaker_stand"],
		[ConsoleStand, &"_restore_console_stand"],
		[SensorBar, &"_restore_sensor_bar"],
		[GcMicrophone, &"_restore_gc_microphone"],
		[N64Vru, &"_restore_n64_vru"],
		[InputReceiver, &"_restore_receiver"],
		[RetroMultitap, &"_restore_multitap"],
		[RetroController, &"_restore_peripheral"],
		[LightGun, &"_restore_peripheral"],
		[RetroMouse, &"_restore_peripheral"],
		[RetroKeyboard, &"_restore_peripheral"],
		[Wiimote, &"_restore_peripheral"],
	]
	return _restore_kinds


# ── Per-type restore hooks (rows of _restore_kind_rows) ─────────────────────────

func _restore_system(root: Node, _id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	var sys := obj as RetroSystem
	# Which composite input each channel's lead goes back into. Absent on every
	# save written before a set had four, and read through a helper that answers
	# Composite 1 for anything it does not cover.
	var tv_inputs: Array = rec.get("tv_inputs", [])
	var tv := _resolve_ref(root, spawned, rec.get("tv")) as RetroTV
	if tv:
		sys.restore_cable_connection(tv, 0, _tv_input(tv_inputs, 0))
	# Extra video-out channels (dual-screen handhelds: ch 1 = BOTTOM). A save
	# made against a model with more channels than this one has is truncated —
	# restore_cable_connection would silently fold the overflow onto ch 0.
	var extra: Array = rec.get("extra_tvs", [])
	for i in range(mini(extra.size(), sys.get_channel_count() - 1)):
		var ch_tv := _resolve_ref(root, spawned, extra[i]) as RetroTV
		if ch_tv:
			sys.restore_cable_connection(ch_tv, i + 1, _tv_input(tv_inputs, i + 1))
	# Its bay first, so the board is seated into the bay's slot and not the cabinet's shut one.
	var bay := _resolve_ref(root, spawned, rec.get("bay")) as ArcadeBayUnit
	if bay:
		sys.restore_bay(bay)
	var cart := _resolve_ref(root, spawned, rec.get("cartridge")) as RetroCartridge
	if cart:
		sys.restore_cartridge(cart, float(rec.get("cartridge_yaw", 0.0)))
	var cart_b := _resolve_ref(root, spawned, rec.get("cartridge_b")) as RetroCartridge
	if cart_b:
		sys.restore_slot2_cartridge(cart_b)
	# Bolt the tower back together. Each unit seats through the same call a
	# hand's release ends in, so a restored stack is the same object graph as
	# a built one: the console knows its units, each unit knows its host, and
	# the launch recipe reads exactly as it would have.
	for ref: Variant in (rec.get("expansions", []) as Array):
		var unit := _resolve_ref(root, spawned, ref) as RetroExpansion
		if unit:
			sys.restore_expansion(unit)
	var memcard := _resolve_ref(root, spawned, rec.get("memcard")) as MemoryCard
	if memcard:
		sys.memcards().restore_memory_card(memcard, 0)
	# Slot B is its own key rather than the pair becoming an array: an array
	# would not load in any room file saved before there was a second slot.
	var memcard_b := _resolve_ref(root, spawned, rec.get("memcard_b")) as MemoryCard
	if memcard_b:
		sys.memcards().restore_memory_card(memcard_b, 1)
	# The expansion-bay lid, if this save had it ON the console. A save with
	# none leaves the bay open, which is a real state: the lid is then a
	# loose object restored from its own entry, wherever it was put down.
	var cover := _resolve_ref(root, spawned, rec.get("expansion_cover")) as ExpansionCover
	if cover:
		sys.restore_expansion_cover(cover)
	# The covers over its own sockets. A console saved before there were any
	# never said its covers were off, so it gets them, over every socket the
	# save left empty; one saved since says which are on, and a cover that is
	# off is restored loose from its own entry.
	if rec.has("port_covers"):
		var covers: Dictionary = rec["port_covers"]
		for socket: Variant in covers:
			var port_cover := _resolve_ref(root, spawned, covers[socket]) as PortCover
			if port_cover:
				sys.restore_port_cover(str(socket), port_cover)
	else:
		sys.seed_port_covers()
	# After the media, and deferred: seating a cartridge swings the bay open (the
	# NES flap) and tweens it there, either of which would otherwise win over the
	# pose the system restored when its model loaded.
	var lid_angle := float(rec.get("lid_angle", -1.0))
	if lid_angle >= 0.0:
		sys.set_lid_angle_deg.call_deferred(lid_angle)
	if rec.has("screen_light"):
		sys.set_screen_light(bool(rec["screen_light"]))
	if rec.has("screen_glow"):
		sys.set_screen_glow(bool(rec["screen_glow"]))


func _restore_arcade_bay(root: Node, _id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	# The board standing in it. Idempotent with the cabinet that plays from it: a snap zone
	# already holding the board does nothing, so whichever restore comes first wins.
	var board := _resolve_ref(root, spawned, rec.get("board")) as Node3D
	var unit := obj as ArcadeBayUnit
	if board and unit.slot != null and unit.get_board() == null:
		unit.slot.pick_up_object(board)


func _restore_expansion(root: Node, _id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	# The disk, disc or cartridge in this unit's own bay. Independent of the
	# order the stack is rebuilt in: a bay seats its media as a pose relative
	# to the unit, so it comes out right whether or not the unit has been
	# bolted to its console yet.
	var own := _resolve_ref(root, spawned, rec.get("media")) as Node3D
	if own:
		(obj as RetroExpansion).restore_media_in_slot(own)
	# Absent from every room saved before a unit had two slots, which is why
	# it is read with a default rather than assumed present.
	var own_b := _resolve_ref(root, spawned, rec.get("media_b")) as Node3D
	if own_b:
		(obj as RetroExpansion).restore_media_in_slot(own_b, 1)
	# Its clip-on accessory (the 32X's Model 2 spacer), on the same terms: a
	# pose relative to the unit, whether or not the unit is seated yet.
	var accessory := _resolve_ref(root, spawned, rec.get("accessory")) as Node3D
	if accessory:
		(obj as RetroExpansion).restore_accessory(accessory)


func _restore_transfer_pak(root: Node, _id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	# The Game Boy cartridge in the pak's roof, on the same terms as an
	# expansion's own bay above: a pose relative to the pak, so it lands right
	# whether or not the pak has been put back into a controller yet.
	var gb := _resolve_ref(root, spawned, rec.get("gb_cart")) as Node3D
	if gb:
		(obj as TransferPak).restore_cart(gb)


func _restore_tv(root: Node, _id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	(obj as RetroTV).restore_control_state(rec.get("controls", {}))
	# The tape or disc in a combination set's own deck. The deck is not an
	# object of its own in the file -- the cabinet builds it -- so what is in it
	# is saved on the set, by the deck's kind.
	var decks: Dictionary = rec.get("decks", {})
	for kind: String in decks:
		var entry: Dictionary = decks[kind]
		var media := _resolve_ref(root, spawned, entry.get("media")) as Node3D
		if media:
			(obj as RetroTV).decks().restore_deck_media(kind, media, float(entry.get("yaw", 0.0)))


func _restore_vcr_player(root: Node, _id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	var tape := _resolve_ref(root, spawned, rec.get("tape")) as VCRTape
	if tape:
		(obj as VCRPlayer).restore_media(tape)


func _restore_dvd_player(root: Node, _id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	var disc := _resolve_ref(root, spawned, rec.get("disc")) as DVDDisc
	if disc:
		(obj as DVDPlayer).restore_media(disc, float(rec.get("disc_yaw", 0.0)))


func _restore_audio_player(root: Node, _id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	var media := _resolve_ref(root, spawned, rec.get("media"))
	if media is AudioDisc or media is AudioCassette or media is VinylRecord:
		(obj as RetroAudioPlayer).restore_media(
			media as Node3D, float(rec.get("media_yaw", 0.0)))


func _restore_speaker_pair(_root: Node, _id: int, obj: Node, _spawned: Dictionary, rec: Dictionary) -> void:
	var pair := obj as SpeakerPair
	pair.set_volume(float(rec.get("volume", 0.75)))
	pair.restore_box_poses(rec.get("boxes", []))


func _restore_surround_amp(_root: Node, _id: int, obj: Node, _spawned: Dictionary, rec: Dictionary) -> void:
	# The switch only: the volume knob came back with every other VRKnob in
	# _restore_articulated_controls above, and its value_changed pushed it.
	(obj as SurroundAmp).restore_state(int(rec.get("decode_mode", 0)))


func _restore_lead(root: Node, _id: int, obj: Node, spawned: Dictionary, saved: Dictionary) -> void:
	# Pass 2, so every deck and set the plugs point at already exists, and for
	# a mains lead so does every wall outlet and every inlet. A plug whose
	# socket cannot be found is simply left where it was saved: a loose end on
	# the floor beats one seated in the wrong device.
	var seats: Array = []
	for rec: Dictionary in saved.get("plugs", []):
		seats.append({
			"end": int(rec.get("end", 0)),
			"cord": int(rec.get("cord", 0)),
			"position": rec.get("position", []),
			"rotation": rec.get("rotation", []),
			"device": _resolve_ref(root, spawned, rec.get("device")) as Node3D,
			"port": str(rec.get("port", "")),
		})
	if obj.has_method("restore_carried_body"):
		obj.call("restore_carried_body", saved.get("body", {}))
	obj.call("restore_seating", seats)


func _restore_speaker_stand(root: Node, _id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	(obj as SpeakerStand).restore_seat(
		_resolve_ref(root, spawned, rec.get("speaker")) as Loudspeaker)


func _restore_console_stand(root: Node, _id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	var sys := _resolve_ref(root, spawned, rec.get("console")) as RetroSystem
	if sys:
		(obj as ConsoleStand).restore_console(sys)


func _restore_sensor_bar(root: Node, _id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	(obj as SensorBar).restore_connection(
		_resolve_ref(root, spawned, rec.get("system")) as RetroSystem)


func _restore_gc_microphone(root: Node, _id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	var mic_slot := int(rec.get("slot", -1))
	var mic_sys := _resolve_ref(root, spawned, rec.get("system")) as RetroSystem
	if mic_slot >= 0 and mic_sys != null:
		(obj as GcMicrophone).restore_seat(mic_sys, mic_slot)


func _restore_n64_vru(root: Node, _id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	var vru_port := int(rec.get("port", -1))
	var vru_sys := _resolve_ref(root, spawned, rec.get("system")) as RetroSystem
	var vru := obj as N64Vru
	if vru_port >= 0 and vru_sys != null:
		vru.restore_seat(vru_sys, vru_port)
	# A save written before the jack existed has no key, and a unit from one
	# came with its microphone attached — so the default is plugged in.
	vru.restore_mic_plugged(bool(rec.get("mic", true)))


func _restore_receiver(root: Node, id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	# A pak goes back whether or not the receiver was plugged into anything —
	# a loose dongle can still have one on it, exactly as a loose N64 pad can.
	# Seated BEFORE the port connection below, so the machine is told what is
	# in the port once, on connecting, rather than told "empty" and corrected.
	if obj is PadReceiver:
		(obj as PadReceiver).restore_pak(
			_resolve_ref(root, spawned, rec.get("pak")) as N64Pak)
		_restore_vmu_slots(obj, root, spawned, rec.get("vmus"))
	var rx_port := int(rec.get("port_index", -1))
	if rx_port < 0:
		return
	var rx_sys := _resolve_ref(root, spawned, rec.get("system")) as RetroSystem
	if rx_sys == null:
		push_warning("[ScenePersistence] pad receiver id=%d: system not found" % id)
		return
	(obj as InputReceiver).restore_port_connection(rx_sys, rx_port)


func _restore_multitap(root: Node, id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	# The pads in its sockets, then its own plug. Both wait for a cord made a
	# frame after spawning, and whichever lands second binds the pads, once.
	var tap := obj as RetroMultitap
	var sockets: Variant = rec.get("sockets", [])
	if sockets is Array:
		for i in mini((sockets as Array).size(), RetroMultitap.SUB_PORTS):
			var held := _resolve_ref(root, spawned, (sockets as Array)[i])
			if held != null:
				tap.restore_socket(i, held)
	var tap_port := int(rec.get("port_index", -1))
	if tap_port < 0:
		return
	var tap_sys := _resolve_ref(root, spawned, rec.get("system")) as RetroSystem
	if tap_sys == null:
		push_warning("[ScenePersistence] multitap id=%d: system not found" % id)
		return
	tap.restore_port_connection(tap_sys, tap_port)


func _restore_peripheral(root: Node, id: int, obj: Node, spawned: Dictionary, rec: Dictionary) -> void:
	# The remote's Nunchuk is restored whether or not it was paired to a
	# console — an unpaired remote can still have one plugged into it.
	if obj is Wiimote:
		# Dongle FIRST. It seats synchronously, and the Nunchuk goes into its
		# pass-through rather than into the remote whenever one is present, so
		# restoring them the other way round puts the Nunchuk in the wrong port.
		(obj as Wiimote).restore_motion_plus(
			_resolve_ref(root, spawned, rec.get("motion_plus")) as MotionPlus)
		(obj as Wiimote).restore_nunchuk(
			_resolve_ref(root, spawned, rec.get("nunchuk")) as Nunchuk)
		# And an extension the game has no class for (a mod's Classic
		# Controller), which goes back the way the Nunchuk does.
		(obj as Wiimote).restore_extension(
			_resolve_ref(root, spawned, rec.get("extension")) as Node3D)
	if obj is RetroController:
		# The pak goes back whether or not the pad was plugged into anything —
		# a loose N64 controller can still have one in it. A Transfer Pak
		# re-seats its own cartridge from its own entry, so this is one call.
		(obj as RetroController).restore_pak(
			_resolve_ref(root, spawned, rec.get("pak")) as N64Pak)
		_restore_vmu_slots(obj, root, spawned, rec.get("vmus"))
	var port_idx := int(rec.get("port_index", -1))
	if port_idx < 0:
		return
	var sys := _resolve_ref(root, spawned, rec.get("system")) as RetroSystem
	if sys == null:
		push_warning("[ScenePersistence] controller id=%d: system not found" % id)
		return
	obj.call("restore_port_connection", sys, port_idx)


# ── Serialization ──────────────────────────────────────────────────────────────

## `{key: yaw}` when a seated disc is turned from its authored seat, else empty,
## so the field is only in the file when it says something. A load reads a
## missing key as 0.0, which is what every room saved before it had.
func _yaw_field(key: String, yaw: float) -> Dictionary:
	if absf(yaw) < 0.0005:
		return {}
	return {key: yaw}


## id, type and pose — the four fields every entry carries. Each branch of
## serialize_node() merges its own fields onto this.
func _base(id: int, type_name: String, n3d: Node3D) -> Dictionary:
	var pos := n3d.global_position
	var rot := n3d.global_rotation_degrees
	var out := {
		"id": id,
		"type": type_name,
		"position": [pos.x, pos.y, pos.z],
		"rotation": [rot.x, rot.y, rot.z],
	}
	# Float-in-place, for the objects that have it (RetroSystem, and every device
	# carrying a FloatLock). Only written when ON, so a room full of ordinary
	# props saves exactly as it did before this field existed.
	var floating := false
	if n3d.has_method("get_ignore_gravity"):
		floating = bool(n3d.call("get_ignore_gravity"))
	elif "ignore_gravity" in n3d:
		floating = bool(n3d.get("ignore_gravity"))
	if floating:
		out["ignore_gravity"] = true
	# Pinned in place. Written only when ON, for the same reason as the flag
	# above: a room of ordinary props saves exactly as it did before it existed.
	if ObjectLock.is_locked(n3d):
		out["locked"] = true
	var articulated := _serialize_articulated_controls(n3d)
	if not articulated.is_empty():
		out["articulated"] = articulated
	var rope_layouts := _serialize_rope_layouts(n3d)
	if not rope_layouts.is_empty():
		out["rope_layouts"] = rope_layouts
	return out


## Which snap zone holds an object, so what a mod built to hold things -- one
## part on another, a console in a stand, a prop on a shelf a mod hung on the
## TV -- comes back holding them rather than as loose bodies standing in the
## same places.
##
## Written for anything held by a MOD's zone: one whose nearest spawned object is
## a mod prop, or one in MOD_ZONE_GROUP (a zone a mod's hook hung on a shipped
## object, or one in a mod's room). The game's own sockets are left out: a
## cartridge in a slot, a plug in a port, a card in a pad each have a field of
## their own and a restore call that does more than seat them (a cartridge's
## yaw, the bay flap, the core), which a bare pick_up_object would get ahead of.
## A plain mod prop has no such field anywhere, so it passes `any_zone` and is
## recorded whatever holds it.
##
## `{"attached": {"to": <ref>, "zone": <path>}}`, or empty when nothing holds it.
## `to` is the spawned object the zone belongs to and `zone` its path inside that
## object, because a zone inside an object has no id of its own. A zone that is
## part of the ROOM has no such object: `to` is then the zone's own path and
## `zone` is ".".
func _attachment_field(n3d: Node3D, node_to_id: Dictionary, any_zone: bool = false) -> Dictionary:
	var pickable := n3d as XRToolsPickable
	if pickable == null:
		return {}
	var zone := pickable.get_picked_up_by() as XRToolsSnapZone
	if zone == null:
		return {}
	# A cell in a battery bay: its object's "cell_slots" says so, roll and all.
	if zone.is_in_group(CellSlots.SLOT_GROUP):
		return {}
	var host: Node = zone
	while host != null and not host.is_in_group("spawned"):
		host = host.get_parent()
	if not any_zone and not _is_mod_zone(zone, host):
		return {}
	if host == null:
		return {"attached": {"to": _ref(node_to_id, zone), "zone": "."}}
	# A spawned host outside the map is a partial serialize (ObjectSync ships one
	# object at a time), and _ref has nothing it could name it by.
	if not node_to_id.has(host):
		return {}
	return {"attached": {"to": node_to_id[host], "zone": str(host.get_path_to(zone))}}


## A zone a mod owns. A mod pad, gun or multitap is not a host here even though
## it carries the stamp: its sockets are the game's (a VMU slot, a pak port, a
## tap's controller sockets), restored by their own fields.
static func _is_mod_zone(zone: Node, host: Node) -> bool:
	if zone.is_in_group(MOD_ZONE_GROUP):
		return true
	return host != null and host.has_meta(MOD_TYPE_META) \
		and not (host is RetroController or host is LightGun or host is RetroMultitap)


## Put an object back in the snap zone _attachment_field recorded. Through the
## zone's own pick_up_object, the call a hand's release ends in, so a restored
## stack is the same object graph as a built one.
func _restore_attachment(root: Node, obj: Node, spawned: Dictionary, saved: Dictionary) -> void:
	var rec: Variant = saved.get("attached")
	if not rec is Dictionary:
		return
	var host := _resolve_ref(root, spawned, (rec as Dictionary).get("to"))
	if host == null:
		return
	var zone := host.get_node_or_null(NodePath(str((rec as Dictionary).get("zone", "."))))
	if not zone is XRToolsSnapZone:
		# The mod moved or renamed the zone since the save; the object stays
		# where it was left, loose.
		push_warning("[ScenePersistence] %s: no snap zone at '%s'" % [obj.name, rec["zone"]])
		return
	(zone as XRToolsSnapZone).pick_up_object(obj as Node3D)


## Articulated child transforms are not represented by the spawned object's
## root pose. Persist every VRHinge by its stable path inside the object so a
## snapshot/reload preserves handheld lids, console flaps and battery covers.
func _serialize_articulated_controls(root: Node3D) -> Array:
	var out: Array = []
	var hinges: Array[Node] = root.find_children("*", "VRHinge", true, false)
	if root is VRHinge:
		hinges.push_front(root)
	for candidate: Node in hinges:
		var hinge := candidate as VRHinge
		if hinge == null or hinge.target == null:
			continue
		var rec := {"path": str(root.get_path_to(hinge))}
		if hinge is VRLever:
			rec["kind"] = "lever"
			rec["value"] = (hinge as VRLever).get_value()
		else:
			rec["kind"] = "hinge"
			rec["value"] = hinge.get_rotation_deg()
			if hinge is VRSpringLatchedHinge:
				rec["latched"] = (hinge as VRSpringLatchedHinge).is_latched_closed()
		out.append(rec)
	for candidate: Node in root.find_children("*", "VRKnob", true, false):
		var knob := candidate as VRKnob
		if knob != null:
			out.append({"path": str(root.get_path_to(knob)),
				"kind": "knob", "value": knob.get_value()})
	for candidate: Node in root.find_children("*", "VRSlider", true, false):
		var slider := candidate as VRSlider
		# A power switch is the one slider whose position is not a pose: it says
		# whether the machine is RUNNING, and nothing restores a running machine.
		# Saved, it brought a handheld back with its switch at ON and a dead
		# console behind it. Its rest position is authored off, and the model puts
		# it back under the machine's control from there (on_power_on/off).
		if slider != null and not slider.is_in_group(RetroSystemModel.POWER_SWITCH_GROUP):
			out.append({"path": str(root.get_path_to(slider)),
				"kind": "slider", "value": slider.value})
	return out


func _restore_articulated_controls(root: Node, records: Array) -> void:
	for raw: Variant in records:
		if not raw is Dictionary:
			continue
		var rec := raw as Dictionary
		var path := str(rec.get("path", ""))
		if path.is_empty() or path.is_absolute_path() or path.length() > 256:
			continue
		var control := root.get_node_or_null(NodePath(path))
		if control == null or (control != root and not root.is_ancestor_of(control)):
			continue
		var kind := str(rec.get("kind", "hinge"))
		var value := float(rec.get("value", rec.get("degrees", NAN)))
		if not is_finite(value):
			continue
		# Model listeners still need the rotation_changed signal to move dependent
		# geometry, but an ObjectSync snapshot must not echo the restore back out.
		control.set_meta("net_restore_in_progress", true)
		match kind:
			"hinge":
				if control is VRSpringLatchedHinge:
					(control as VRSpringLatchedHinge).set_state_remote(value,
						bool(rec.get("latched", false)))
				elif control is VRHinge:
					(control as VRHinge).set_rotation_deg_remote(value)
			"lever":
				if control is VRLever:
					(control as VRLever).set_value(value)
			"knob":
				if control is VRKnob:
					(control as VRKnob).set_value(value)
			"slider":
				# The group check is here as well as in the save walk: every slot
				# written before this one carries the switch, and applying it would
				# also fire value_changed straight into toggle_power.
				if control is VRSlider \
						and not control.is_in_group(RetroSystemModel.POWER_SWITCH_GROUP):
					(control as VRSlider).set_value(value)
				elif control is VRKnob:
					# A handheld's volume saved while it was a slider, now its
					# thumbwheel: the same path and the same 0..1.
					(control as VRKnob).set_value(value)
		control.remove_meta("net_restore_in_progress")


## Save world-space particles, keyed by a stable path inside the spawned object.
## Endpoints alone cannot reconstruct which side of a table, post or partition a
## player routed a lead around.
func _serialize_rope_layouts(root: Node3D) -> Array:
	var layouts: Array = []
	var ropes: Array[Node] = root.find_children("*", "VerletRope", true, false)
	if root is VerletRope:
		ropes.push_front(root)
	for child: Node in ropes:
		var rope := child as VerletRope
		if rope == null:
			continue
		var encoded: Array = []
		for point: Vector3 in rope.get_points():
			encoded.append([point.x, point.y, point.z])
		if not encoded.is_empty():
			layouts.append({
				"path": str(root.get_path_to(rope)),
				"points": encoded,
			})
	return layouts


## What is in a combination set's built-in decks, as {"decks": {kind: {media, yaw}}},
## or nothing at all for a set without one -- so every other set writes the same
## bytes it always did.
func _tv_decks_field(tv: RetroTV, node_to_id: Dictionary) -> Dictionary:
	if tv.decks() == null:
		return {}
	var state := tv.decks().media_state(func(media: Node) -> Variant:
		return _ref(node_to_id, media))
	return {"decks": state} if not state.is_empty() else {}


## The console entry, lifted out of _serialize_kind's type table.
##
## It is the one branch there that is more than a field map: five of its keys are
## written conditionally, two of them from loops over the machine's channels, so
## it carried as many lines as the next eight branches together.
func _serialize_system(sys: RetroSystem, id: int, n3d: Node3D,
		node_to_id: Dictionary) -> Dictionary:
	var result := _base(id, "system", n3d).merged({
		"systemid": sys.systemid,
		"model_id": sys.model_id,
		"tv": _ref(node_to_id, sys.connected_tv),
		"cartridge": _ref(node_to_id, sys.get_snapped_cartridge()),
		# The DS's GBA slot. Its own key, as memcard_b is, so a room saved before
		# there was a second slot still loads.
		"cartridge_b": _ref(node_to_id, sys.get_slot2_cartridge()),
		# Cards only: a GameCube Microphone's plug is seated here too, and it is
		# restored from the stick's own entry.
		"memcard": _ref(node_to_id, sys.memcards().get_snapped_memcard(0) as MemoryCard),
		"memcard_b": _ref(node_to_id, sys.memcards().get_snapped_memcard(1) as MemoryCard),
		# Null once a player has pulled the lid off and put it down — a
		# state worth keeping, since the pak under it is only reachable
		# while the lid stays off.
		"expansion_cover": _ref(node_to_id, sys.get_expansion_cover()),
		"video_out": sys.video_out_enabled,
		"ignore_gravity": sys.ignore_gravity,
	})
	# A cabinet with its art taken off; omitted while it is on (the default), so no room changes.
	if not sys.cabinet_art_enabled:
		result["cabinet_art"] = false
	# A cabinet that was told to attract or not to; omitted while it follows the global pref.
	if sys.attract_override != ArcadeAttract.OVERRIDE_FOLLOW:
		result["attract"] = sys.attract_override
	# A cabinet whose power button is a switch, left ON: it is found on again when the room loads.
	# Omitted while it is off, so no room without a switched-on cabinet changes.
	if sys.attract_switched_on():
		result["attract_on"] = true
	# A cabinet playing from a separate bay: the board is the BAY's (its entry names it), and the
	# bay is recorded here when it is clipped into the mount. A cabled one is the lead's.
	var bay := sys.get_bay()
	if bay != null:
		result["cartridge"] = _ref(node_to_id, null)
		if sys.bay_link_kind() == ArcadeBayUnit.DOCK:
			result["bay"] = _ref(node_to_id, bay)
	# Which image the memory built into it is. Omitted on a machine with none, so
	# no room without a Saturn or a 3DO in it changes at all.
	if sys.console_memory() != null:
		result["console_memory"] = sys.console_memory().card_id
	# What is bolted to this machine. Written from the CONSOLE rather than
	# from each unit because that is the side which seats them -- one
	# restore_expansion call per unit, whichever way round a given pair
	# stacks -- and because it keeps a whole tower in one entry, in the order
	# it was built. Omitted when nothing is attached, so no room file that
	# has no stack in it changes at all.
	var units: Array = []
	for unit in sys.get_expansions():
		units.append(_ref(node_to_id, unit))
	if not units.is_empty():
		result["expansions"] = units
	# Written for every console whose model has covers, null for one that is off,
	# so that a console with no "port_covers" at all is one saved before covers
	# and is given them on load. Omitted on every other console, which changes no
	# room without one.
	var covers := sys.get_port_covers()
	if not covers.is_empty():
		var refs := {}
		for socket: String in covers:
			refs[socket] = _ref(node_to_id, covers[socket] as Node)
		result["port_covers"] = refs
	# Which physical gamepad drives it, for handhelds — they have no port to
	# take a PadReceiver, so the choice lives on the machine. Written only
	# when one is set, so nothing changes for the rooms that never touch it.
	if not sys.pad_guid.is_empty():
		result["pad_guid"] = sys.pad_guid
		result["pad_ordinal"] = sys.pad_ordinal
	# The core the player picked for THIS machine (empty = its system's default).
	if not sys.core_name.is_empty():
		result["core_name"] = sys.core_name
	# Clamshell lid angle (DS/3DS); omitted for systems without a lid.
	var lid_angle := sys.get_lid_angle_deg()
	if lid_angle >= 0.0:
		result["lid_angle"] = lid_angle
	# A screen light switched OFF (GBA SP); on is the default and goes unsaved.
	if sys.get_screen_light() == 0:
		result["screen_light"] = false
	# "Self-Lit Screen" switched ON; off is the default and goes unsaved.
	if sys.get_screen_glow() == 1:
		result["screen_glow"] = true
	# Extra video-out channels (dual-screen handhelds: ch 1 = BOTTOM).
	var extra: Array = []
	for ch in range(1, sys.get_channel_count()):
		extra.append(_ref(node_to_id, sys.get_channel_tv(ch)))
	if not extra.is_empty():
		result["extra_tvs"] = extra
	# Which composite input each lead is in, one per channel. Omitted while they
	# are all in Composite 1, which is what a save without the key restores to —
	# so the common case adds nothing to the file.
	var tv_inputs: Array = []
	var any_input := false
	for ch in sys.get_channel_count():
		var input := sys.get_channel_tv_input(ch)
		any_input = any_input or input != 0
		tv_inputs.append(input)
	if any_input:
		result["tv_inputs"] = tv_inputs
	# The spin a disc was seated at, so it comes back the way the hand put it
	# in. Omitted while square, so a room of cartridges writes nothing new.
	result.merge(_yaw_field("cartridge_yaw", sys.cartridge_seat_yaw()))
	return result


## One object's save entry: its kind's fields, its colour and whatever else every
## kind carries. `id` is the number it is saved under and `node_to_id` maps the
## room's objects to theirs, so a reference to another object can be written as
## that object's number. Public because netplay's object sync builds its wire
## entries through it and the suites assert the entry a room would write.
func serialize_node(node: Node, id: int, node_to_id: Dictionary) -> Dictionary:
	var entry := _serialize_kind(node, id, node_to_id)
	# Which of its colors it is, for anything that is one of several: a console,
	# a bay lid, a controller a mod dressed. Only then, so everything else saves
	# exactly as it did.
	if not entry.is_empty():
		var variant := SystemModelRegistry.variant_of(node)
		if not variant.is_empty():
			entry["model_variant"] = variant
		# A plain mod prop has already said what holds it, from any zone.
		if not entry.has("attached"):
			entry.merge(_attachment_field(node as Node3D, node_to_id))
		var cover_slots := _cover_slots_field(node, node_to_id)
		if not cover_slots.is_empty():
			entry["cover_slots"] = cover_slots
		var cell_slots := _cell_slots_field(node, node_to_id)
		if not cell_slots.is_empty():
			entry["cell_slots"] = cell_slots
	return entry


## The removable covers a mod gave an object (CoverSlots): each slot and its
## cover, null for one that is off. Written for every object with a slot, so one
## with no "cover_slots" at all is one saved before it had covers, and is given
## them on load. Omitted on everything else, which saves exactly as it did.
func _cover_slots_field(node: Node, node_to_id: Dictionary) -> Dictionary:
	var slots := CoverSlots.of(node)
	if slots == null:
		return {}
	var refs := {}
	var covers := slots.covers()
	for socket: String in covers:
		refs[socket] = _ref(node_to_id, covers[socket] as Node)
	return refs


## Hand an object's covers back, whether its slots are built yet or not
## (CoverSlots.told): the save's cover for each, null for one that was off, and
## nothing for a slot the save does not name, which gets a fresh cover.
func _restore_cover_slots(root: Node, obj: Node, spawned: Dictionary, entry: Dictionary) -> void:
	var saved := {}
	var rec: Variant = entry.get("cover_slots")
	if rec is Dictionary:
		for socket: Variant in (rec as Dictionary):
			saved[str(socket)] = _resolve_ref(root, spawned, (rec as Dictionary)[socket])
	CoverSlots.told(obj, saved)


## The battery cells in an object's bays (CellSlots): each seat with a cell in it,
## the cell and the roll it went in at, in degrees. Empty seats are left out, and
## so is the field on an object with none in.
func _cell_slots_field(node: Node, node_to_id: Dictionary) -> Dictionary:
	var slots := CellSlots.of(node)
	if slots == null:
		return {}
	var out := {}
	var cells := slots.cells()
	for seat: String in cells:
		var rec := cells[seat] as Array
		var ref: Variant = _ref(node_to_id, rec[0] as Node)
		if ref == null:
			continue
		out[seat] = {"cell": ref, "roll": snappedf(rad_to_deg(float(rec[1])), 0.01)}
	return out


## Hand an object's cells back, whether its slots are built yet or not
## (CellSlots.told): seat -> [the cell, its roll in radians].
func _restore_cell_slots(root: Node, obj: Node, spawned: Dictionary, entry: Dictionary) -> void:
	var rec: Variant = entry.get("cell_slots")
	if not rec is Dictionary:
		return
	var saved := {}
	for seat: Variant in (rec as Dictionary):
		var one: Variant = (rec as Dictionary)[seat]
		if not one is Dictionary:
			continue
		var cell := _resolve_ref(root, spawned, (one as Dictionary).get("cell"))
		if cell != null:
			saved[str(seat)] = [cell, deg_to_rad(float((one as Dictionary).get("roll", 0.0)))]
	CellSlots.told(obj, saved)


## The save side's registry: which class saves as which type, and what it writes
## besides its pose. One row per class, in one of three shapes:
##
##   [Class, "type"]               pose only -- _base and nothing else
##   [Class, "type", &"_fields"]   _base, merged with what _fields(node, node_to_id)
##                                 returns (the keys after the pose, in its order)
##   [Class, "", &"_entry"]        _entry(node, id, n3d, node_to_id) writes the whole
##                                 entry: its type is not fixed by the class (a
##                                 battery's size, a deck's kind, which pad) or it is
##                                 more than a field map (a console, a lead)
##
## ORDERED, not a lookup: _serialize_kind walks it top to bottom and the FIRST row
## the node `is` wins, exactly as the `elif node is X` chain it replaced did. `is`
## matches every ancestor, so a subclass's row must come before its base's. Where
## that matters today: RetroDisc before RetroCartridge (it extends it), and
## SnesMouse before RetroMouse inside _serialize_peripheral. A MediaTransport built
## into a set is refused before the walk (_serialize_kind).
##
## A type restored from PLAIN_SCENES still needs its row HERE: that map is read
## only when LOADING, and an object with no row is never written, so there is
## nothing to load back. That drift shipped for the Nunchuk, the Jump Pack, the
## Motion Plus, the table and the i.LINK hub, each of which went missing from saved
## rooms; scene_tests' registry/ cases check every PLAIN_SCENES type is written.
##
## Built on first use rather than as a const: the rows hold class scripts, and
## reading them at serialize time is after every one of those scripts has loaded.
static var _save_kinds: Array = []

static func _save_kind_rows() -> Array:
	if not _save_kinds.is_empty():
		return _save_kinds
	_save_kinds = [
		[RetroSystem, "", &"_serialize_system"],
		[RetroTV, "tv", &"_tv_fields"],
		# Pose, plus which console is powering it. Unlike the Nunchuk this end DOES
		# mean something: the bar is what a remote looks at, and a bar restored
		# unplugged is a room where nothing points at anything.
		[SensorBar, "sensor_bar", &"_sensor_bar_fields"],
		# Pose only. Which remote it is plugged into is saved on the REMOTE, which
		# is the end of the cord that means something; this side is just where the
		# thing is lying.
		[Nunchuk, "nunchuk"],
		# Card fields as well as a pose: each of these IS its image on disk, and one
		# that came back without its card_id would mint a new blank and read as a
		# wiped set of notes. Which controller holds it (and which of a pad's two
		# slots) is saved on the CONTROLLER.
		[ControllerPak, "controller_pak", &"_card_fields"],
		[VmuCard, "vmu", &"_card_fields"],
		[XboxMuCard, "xbox_mu", &"_card_fields"],
		# The cartridge in its roof is a reference rather than a pose, so a pak put
		# away with a game still in it comes back holding that same game.
		[TransferPak, "transfer_pak", &"_transfer_pak_fields"],
		# Pose only: none of these carries state of its own. Which controller, 32X
		# or pad slot each is in is saved on the thing it is in.
		[RumblePak, "rumble_pak"],
		[Sega32xSpacer, "sega32x_spacer"],
		[JumpPack, "jump_pack"],
		# Pose only, for the Jump Pack's reason; the bay it is in is on the thing
		# the bay belongs to. Its type is its size, which the cell answers for.
		[BatteryCell, "", &"_battery_entry"],
		[DcMicrophone, "dc_microphone"],
		# The plug is on the cord rather than an entry of its own, so the stick
		# records where it is seated.
		[GcMicrophone, "gc_microphone", &"_gc_microphone_fields"],
		# The microphone and both cords ride with the unit and have no entries of
		# their own, so the unit records the socket it is in — and whether its
		# microphone is in its jack, which is a thing a player can undo.
		[N64Vru, "n64_vru", &"_n64_vru_fields"],
		# Pose only, for the Nunchuk's reason: which remote it is seated in is saved
		# on that remote.
		[MotionPlus, "motion_plus"],
		[TVRemote, "tv_remote"],
		[StorageBox, "trash_can"],
		# Pose only: which lead is in which of a hub's sockets is recorded by each
		# LEAD, naming the hub and "PortN".
		[ILinkHub, "ilink_hub"],
		# The pose and the roll it is loaded with.
		[GbPrinter, "gb_printer", &"_gb_printer_fields"],
		[EthernetHub, "ethernet_hub"],
		# The pose and the board standing in it; its type is its kind's.
		[ArcadeBayUnit, "", &"_arcade_bay_entry"],
		[Table, "table"],
		[RetroExpansion, "expansion", &"_expansion_fields"],
		# MUST precede the RetroCartridge row — RetroDisc extends it.
		[RetroDisc, "disc", &"_media_fields"],
		[RetroCartridge, "cartridge", &"_media_fields"],
		[MemoryCard, "memory_card", &"_memory_card_fields"],
		# Nothing to record but its existence and where it is: a lid is
		# interchangeable, and which console it belongs on comes from that
		# console's own "expansion_cover" reference. (Its color, for a lid that
		# was given one, is written by serialize_node as anything's is.)
		[ExpansionCover, "expansion_cover"],
		[PortCover, "port_cover", &"_port_cover_fields"],
		[Poster, "poster", &"_poster_fields"],
		[PDFBook, "book", &"_book_fields"],
		# The deck's own TV link is not saved: the lead is a separate object now, so
		# the connection lives in a spawned cable's plugs. Same for the DVD player.
		[VCRPlayer, "vcr_player", &"_vcr_player_fields"],
		[VCRTape, "vcr_tape", &"_vcr_tape_fields"],
		[DVDPlayer, "dvd_player", &"_dvd_player_fields"],
		[DVDDisc, "dvd_disc", &"_dvd_disc_fields"],
		[RetroAudioPlayer, "", &"_audio_player_entry"],
		[AudioDisc, "audio_disc", &"_album_fields"],
		[AudioCassette, "audio_cassette", &"_audio_cassette_fields"],
		[VinylRecord, "vinyl_record", &"_album_fields"],
		# One builder for the whole family; it picks the type (_serialize_peripheral).
		[RetroController, "", &"_serialize_peripheral"],
		[LightGun, "", &"_serialize_peripheral"],
		[RetroMouse, "", &"_serialize_peripheral"],
		[RetroKeyboard, "", &"_serialize_peripheral"],
		[Wiimote, "", &"_serialize_peripheral"],
		[RetroMultitap, "", &"_serialize_multitap"],
		[Loudspeaker, "", &"_loudspeaker_entry"],
		[SpeakerStand, "", &"_speaker_stand_entry"],
		# Which stand, and the console mounted in it: the STAND records it, for
		# SpeakerStand's reason (the zone is the stand's, and a console knows
		# nothing about stands).
		[ConsoleStand, "console_stand", &"_console_stand_fields"],
		[SurroundAmp, "surround_amp", &"_surround_amp_fields"],
		# Deliberately not a pose-only object. The root never moves — the two
		# cabinets are separate bodies the player carries around one at a time — so
		# the root's transform says nothing about where either of them is.
		[SpeakerPair, "speaker_pair", &"_speaker_pair_fields"],
		[KeyboardReceiver, "keyboard_receiver", &"_receiver_fields"],
		[MouseReceiver, "mouse_receiver", &"_receiver_fields"],
		[PadReceiver, "pad_receiver", &"_pad_receiver_fields"],
		[CompositeCable, "", &"_serialize_cable"],
		[PowerCord, "", &"_serialize_power_cord"],
		[PowerStrip, "", &"_serialize_power_strip"],
		[TravelAdapter, "", &"_serialize_travel_adapter"],
	]
	return _save_kinds


## Every type a row of _save_kind_rows() writes under a fixed name. The rows whose
## builder picks the type at save time are not in it; scene_tests' registry/ cases
## account for those by name.
static func saved_kind_types() -> Array:
	var out: Array = []
	for row: Array in _save_kind_rows():
		if not str(row[1]).is_empty():
			out.append(str(row[1]))
	return out


func _serialize_kind(node: Node, id: int, node_to_id: Dictionary) -> Dictionary:
	if not node is Node3D:
		return {}
	var n3d := node as Node3D

	# A mod prop is identified by the metadata its spawn stamped on it, not by a
	# class test: there is no class to test for, because the whole point is that
	# the mod supplies the scene. Checked FIRST so a mod object whose root
	# happens to derive from a known type is still written as itself rather than
	# as its base class, which would lose the scene it came from.
	# A mod's PAD is not one of these, and is left to the controller row below.
	# That row already writes the scene a pad came from, which is how every pad
	# is told apart, and with it the port it is plugged into. Written here as a
	# bare pose, a mod's pad came back as the right pad, unplugged. A mod's LIGHT
	# GUN is the same case: it is in a port too, and that row is where the port
	# is written. So is a mod's MULTITAP, which has pads in it besides.
	if node.has_meta(MOD_TYPE_META) \
			and not (node is RetroController or node is LightGun or node is RetroMultitap):
		var mod_type := str(node.get_meta(MOD_TYPE_META))
		# A mod's LEAD is still a lead. Written as a pose alone it came back as
		# the right scene lying on the floor with nothing plugged in, because
		# where a lead's ends are IS where it is. So it takes the lead's own
		# entry under the mod's type; both restore passes read a lead by class.
		var lead := _serialize_lead(node, id, n3d, node_to_id)
		if lead.is_empty():
			var prop := _base(id, mod_type, n3d)
			prop.merge(_attachment_field(n3d, node_to_id, true))
			return prop
		lead["type"] = mod_type
		return lead

	# A deck built into a set is the set's, and saved on it (_tv_decks_field).
	# Never in "spawned" today; refused here too, so a set restored with one
	# could never come back with a second, loose copy beside it. No row above the
	# decks' could match a MediaTransport, so testing it before the walk is the
	# same as testing it where the chain used to.
	if node is MediaTransport and (node as MediaTransport).built_into != null:
		return {}

	for row: Array in _save_kind_rows():
		if not is_instance_of(node, row[0]):
			continue
		var type_name := str(row[1])
		if row.size() < 3:
			return _base(id, type_name, n3d)
		var hook := row[2] as StringName
		if type_name.is_empty():
			var entry: Dictionary = call(hook, node, id, n3d, node_to_id)
			return entry
		var fields: Dictionary = call(hook, node, node_to_id)
		return _base(id, type_name, n3d).merged(fields)
	return {}


# ── Per-type save hooks (rows of _save_kind_rows) ──────────────────────────────
# A `_fields` hook returns the keys written after the pose; an `_entry` hook the
# whole entry.

func _tv_fields(tv: RetroTV, node_to_id: Dictionary) -> Dictionary:
	return {
		# Which cabinet it wears. Without this a spawned monitor comes back as
		# the stock black box, since tv_model only ever survived by being
		# authored into a scene.
		"tv_model": tv.tv_model,
		"crt_enabled": tv.crt_enabled,
		"crt_params": tv.get_crt_params(),
		"scale_factor": tv.scale_factor,
		"stereo_mode": tv.stereo_mode,
		"controls": tv.get_control_state(),
	}.merged(_tv_decks_field(tv, node_to_id))


func _sensor_bar_fields(bar: SensorBar, node_to_id: Dictionary) -> Dictionary:
	return {"system": _ref(node_to_id, bar.get_system())}


## The identity of anything that IS an image on disk: a Controller Pak, a VMU, an
## Xbox Memory Unit, a memory card, an expansion unit's own memory. Read
## duck-typed, since those share no base class; _apply_card_fields is the way back.
func _card_fields(card: Node, _node_to_id: Dictionary = {}) -> Dictionary:
	return {
		"card_id": card.get("card_id"),
		"card_label": card.get("card_label"),
	}


func _transfer_pak_fields(pak: TransferPak, node_to_id: Dictionary) -> Dictionary:
	return {"gb_cart": _ref(node_to_id, pak.get_cart())}


func _battery_entry(cell: BatteryCell, id: int, n3d: Node3D,
		_node_to_id: Dictionary) -> Dictionary:
	return _base(id, cell.save_type(), n3d)


## The pose and the board standing in it. Whether it is in a cabinet's mount is on the
## cabinet's entry, and a cabled one is the lead's; the board is here because a bay standing
## alone with a game in it has nobody else to remember it.
func _arcade_bay_entry(bay: ArcadeBayUnit, id: int, n3d: Node3D, node_to_id: Dictionary) -> Dictionary:
	return _base(id, bay.type_id, n3d).merged({"board": _ref(node_to_id, bay.get_board())})


func _gc_microphone_fields(mic: GcMicrophone, node_to_id: Dictionary) -> Dictionary:
	return {
		"system": _ref(node_to_id, mic.seated_system()),
		"slot": mic.seated_slot(),
	}


func _n64_vru_fields(vru: N64Vru, node_to_id: Dictionary) -> Dictionary:
	return {
		"system": _ref(node_to_id, vru.seated_system),
		"port": vru.seated_port_index,
		"mic": vru.mic_plugged(),
	}


func _gb_printer_fields(printer: GbPrinter, _node_to_id: Dictionary) -> Dictionary:
	return {"paper": printer.paper_roll}


## The unit, and whatever is in its OWN bay. Which console it is bolted to is
## deliberately not written here -- it is in that console's entry, so a stack is
## described once instead of from both ends, where the two could disagree about
## what is attached to what.
func _expansion_fields(unit: RetroExpansion, node_to_id: Dictionary) -> Dictionary:
	var fields := {
		"expansion_id": unit.expansion_id,
		# The ROM a unit carries in itself -- the BS-X shell. Without this a
		# restored BS-X cartridge came back as an empty enclosure that booted
		# nothing, and the room looked right while the machine was dead.
		"rom_path": unit.rom_path,
		"media": _ref(node_to_id, unit.get_media()),
		# Slot B is its own key rather than the pair becoming an array, for
		# the same reason the second memory card is: an array would not load
		# in any room file saved before there was a second slot.
		"media_b": _ref(node_to_id, unit.get_media(1)),
		# What is clipped on -- the 32X's Model 2 spacer. Absent from every
		# room saved before units took accessories, so read with a default.
		"accessory": _ref(node_to_id, unit.get_accessory()),
	}
	# The unit's own memory, so its saves come back with it and are not minted
	# afresh under a new name.
	return fields.merged(_card_fields(unit))


func _memory_card_fields(card: MemoryCard, _node_to_id: Dictionary) -> Dictionary:
	return {"family": card.family}.merged(_card_fields(card))


func _port_cover_fields(cover: PortCover, _node_to_id: Dictionary) -> Dictionary:
	return {
		"cover_socket": cover.socket_id,
		"cover_size": [cover.size.x, cover.size.y, cover.size.z],
	}


func _poster_fields(poster: Poster, _node_to_id: Dictionary) -> Dictionary:
	var fields := {
		"image_path": poster.image_path,
		"size_scale": poster.size_scale,
		"fit_mode": int(poster.fit_mode),
		"roll": poster.roll_degrees,
		"stuck": poster.is_stuck(),
	}
	# Only when switched off, so every other poster saves as it did.
	if not poster.sticks:
		fields["sticks"] = false
	# Only on a Game Boy Printer's print, so every other poster saves as it did.
	if poster.printout:
		fields["printout"] = true
	return fields


func _book_fields(book: PDFBook, _node_to_id: Dictionary) -> Dictionary:
	var page := book.net_get_page()
	return {
		"pdf_path": book.pdf_path,
		"half_pages": book.half_page_mode,
		"size_scale": book.size_scale,
		"hardback": book.hardback,
		"page_state": int(page.get("state", 0)),
		"page_leaf": int(page.get("leaf", 0)),
	}


func _vcr_player_fields(vcr: VCRPlayer, node_to_id: Dictionary) -> Dictionary:
	return {"tape": _ref(node_to_id, vcr.get_snapped_tape())}


func _vcr_tape_fields(tape: VCRTape, _node_to_id: Dictionary) -> Dictionary:
	return {
		"video_path": tape.video_path,
		"video_label": tape.video_label,
		# Where its tape stands. A tape in a deck is saved as itself and
		# seated afterward, so the deck reads these as it takes it back.
		"tape_track": tape.tape_track,
		"tape_time": tape.tape_time,
		"tape_progress": tape.tape_progress,
		# Which cassette it is, how long its recordings are, and how far
		# into the blank tape after them it stands.
		"cassette": tape.cassette,
		"recording_seconds": tape.recording_seconds,
		"tape_blank": tape.tape_blank,
	}


func _dvd_player_fields(dvdp: DVDPlayer, node_to_id: Dictionary) -> Dictionary:
	return {
		"disc": _ref(node_to_id, dvdp.get_snapped_disc()),
	}.merged(_yaw_field("disc_yaw", dvdp.disc_seat_yaw()))


func _dvd_disc_fields(dvd: DVDDisc, _node_to_id: Dictionary) -> Dictionary:
	return {
		"dvd_path": dvd.dvd_path,
		"dvd_label": dvd.dvd_label,
	}


## The deck answers for its own type. This used to be
## `"cd_player" if node is CDPlayer else "cassette_player"`, whose else-arm
## silently saved any third deck as a cassette — a turntable came back a tape
## machine. A virtual makes a deck that forgets to override a missing string
## rather than another deck's.
func _audio_player_entry(ap: RetroAudioPlayer, id: int, n3d: Node3D,
		node_to_id: Dictionary) -> Dictionary:
	return _base(id, ap.deck_save_type(), n3d).merged({
		"media": _ref(node_to_id, ap.get_snapped_media()),
	}).merged(_yaw_field("media_yaw", ap.media_seat_yaw()))


## An audio disc's or a record's: which album, and what it is called. Read
## duck-typed, since the two share no base class.
func _album_fields(media: Node, _node_to_id: Dictionary) -> Dictionary:
	return {
		"album_path": media.get("album_path"),
		"album_label": media.get("album_label"),
	}


func _audio_cassette_fields(acass: AudioCassette, node_to_id: Dictionary) -> Dictionary:
	return _album_fields(acass, node_to_id).merged({
		# Where its tape stands. A cassette in a deck is saved as itself and
		# seated afterward, so the deck reads these as it takes it back.
		"tape_track": acass.tape_track,
		"tape_time": acass.tape_time,
		"tape_progress": acass.tape_progress,
	})


## Pose only: one cabinet, and which channel it carries is not its own state —
## it is decided by the television socket its lead sits in, and the lead records
## that itself. Two scenes share the class, so the type comes off the scene file
## rather than the class.
func _loudspeaker_entry(speaker: Loudspeaker, id: int, n3d: Node3D,
		_node_to_id: Dictionary) -> Dictionary:
	var token := "subwoofer" if speaker.scene_file_path.ends_with("subwoofer.tscn") \
		else "loudspeaker"
	return _base(id, token, n3d)


## The STAND records the cabinet on it, not the other way round: the seat is the
## stand's, and Loudspeaker knows nothing about stands. Without it a restored
## cabinet would come back at the right height but unseated, so it would merely
## REST on the plate — stable, but knocked off by a lead.
func _speaker_stand_entry(stand: SpeakerStand, id: int, n3d: Node3D,
		node_to_id: Dictionary) -> Dictionary:
	var stand_token := "speaker_stand_100" \
		if stand.scene_file_path.ends_with("speaker_stand_100.tscn") \
		else "speaker_stand_120"
	return _base(id, stand_token, n3d).merged({
		"speaker": _ref(node_to_id, stand.seated_speaker()),
	})


func _console_stand_fields(stand: ConsoleStand, node_to_id: Dictionary) -> Dictionary:
	return {
		"stand_id": stand.stand_id,
		"console": _ref(node_to_id, stand.seated_console()),
	}


## The decoder switch as well as the pose. The volume knob is a VRKnob, which
## _base already records with the other articulated controls; which machine it
## carries and which cabinets are on its back are the LEADS' to record.
func _surround_amp_fields(amp: SurroundAmp, _node_to_id: Dictionary) -> Dictionary:
	return {"decode_mode": amp.decode_mode}


func _speaker_pair_fields(pair: SpeakerPair, _node_to_id: Dictionary) -> Dictionary:
	return {
		"boxes": pair.box_poses(),
		"volume": pair.get_volume(),
	}


## Which port it is seated in — everything a receiver has in common. The socket,
## like every other peripheral's, is the CABINET's rather than the libretro port
## (see _serialize_peripheral).
func _receiver_fields(rx: InputReceiver, node_to_id: Dictionary) -> Dictionary:
	var sys: Node = rx.get_connected_system()
	var port := -1
	if sys != null and sys.has_method("cabinet_port_of"):
		port = int(sys.call("cabinet_port_of", rx))
	return {
		"system": _ref(node_to_id, sys),
		"port_index": port,
	}


## Which PAD it is for as well as which port it is in — a receiver with no pad is
## a dongle for nothing.
func _pad_receiver_fields(pr: PadReceiver, node_to_id: Dictionary) -> Dictionary:
	var fields := _receiver_fields(pr, node_to_id).merged({
		"pad_guid": pr.pad_guid,
		"pad_name": pr.pad_name,
		"pad_ordinal": pr.pad_ordinal,
	})
	# Which pak is on its boss, saved on the RECEIVER for the reason the
	# controller's is saved on the pad: the port is the end that means
	# something, and the pak's own entry is only where it is lying.
	var pr_pak: Node = pr.get_pak()
	if pr_pak != null:
		fields["pak"] = _ref(node_to_id, pr_pak)
	var pr_vmus := _vmu_slot_refs(pr, node_to_id)
	if not pr_vmus.is_empty():
		fields["vmus"] = pr_vmus
	return fields


func _media_fields(cart: RetroCartridge, _node_to_id: Dictionary = {}) -> Dictionary:
	var fields := {
		"rom_path": cart.rom_path,
		"game_label": cart.game_label,
		"save_id": cart.save_id,
		"cart_systemid": cart.systemid,
	}
	# Only what was forced: a cartridge left alone derives both from its ROM.
	if not cart.shell_preset.is_empty():
		fields["shell_preset"] = String(cart.shell_preset)
	if not cart.shell_color.is_empty():
		fields["shell_color"] = cart.shell_color
	if cart.shell_flake:
		fields["shell_flake"] = true
	if not cart.body_region.is_empty():
		fields["body_region"] = cart.body_region
	# Only a cartridge whose ROM names no region carries one (see _pin_fallback_market).
	if not cart.fallback_market.is_empty():
		fields["fallback_market"] = cart.fallback_market
	return fields


func _serialize_peripheral(node: Node, id: int, n3d: Node3D, node_to_id: Dictionary) -> Dictionary:
	var obj_type := "retro_controller"
	if node is Wiimote:
		obj_type = "wiimote"
	elif node is LightGun:
		obj_type = "light_gun"
	elif node is SnesMouse:
		# Before the RetroMouse arm, which it also satisfies — reaching that
		# first would save the SNES mouse as the primitive one and hand the
		# player a grey box back.
		obj_type = "snes_mouse"
	elif node is RetroMouse:
		obj_type = "retro_mouse"
	elif node is RetroKeyboard:
		obj_type = "retro_keyboard"
	var connected_sys: Node = node.get_connected_system()
	# A pad in a multitap's socket is the TAP's to put back (its "sockets"). The
	# console files it under the port the tap fans out to, a number that is also
	# one of the console's own sockets, so writing it here plugged the pad
	# straight into the console on the next load.
	if connected_sys != null and _multitap_holding(node, node_to_id) != null:
		connected_sys = null
	# The CABINET socket, which is what restore_controller_plug takes — not the
	# peripheral's own _port_index, which is the libretro port and is pinned to 0
	# for a mouse on a computer system. Falls back to it for anything the cabinet
	# does not claim to be holding.
	var port_index := -1
	if connected_sys != null:
		port_index = node.get_port_index()
		if connected_sys.has_method("cabinet_port_of"):
			var socket: int = connected_sys.call("cabinet_port_of", node)
			if socket >= 0:
				port_index = socket
	var entry := _base(id, obj_type, n3d).merged({
		"device_type": node.get("device_type") as int,
		"system": _ref(node_to_id, connected_sys),
		"port_index": port_index,
	})
	if node is Wiimote:
		# Which Nunchuk is plugged into this remote, if any. Saved on the REMOTE
		# because that is the end of the cord that means something — the nunchuk
		# itself is just a pose.
		entry["nunchuk"] = _ref(node_to_id, (node as Wiimote).get_nunchuk())
		# And the dongle, if one is fitted. Saved beside the Nunchuk rather than
		# derived from device_type, because the pair of them is what says which
		# port the Nunchuk goes back into.
		entry["motion_plus"] = _ref(node_to_id, (node as Wiimote).get_motion_plus())
		# An extension of a mod's making, when there is one: the remote is asked
		# what is on the end of it, straight in or through the dongle. Left out
		# of the entry when there is none, so a save without one is as it was.
		var extension := (node as Wiimote).get_extension()
		if extension != null:
			entry["extension"] = _ref(node_to_id, extension)
	if node is RetroMouse:
		entry["sensitivity"] = (node as RetroMouse).sensitivity
		entry["stick_distance"] = (node as RetroMouse).stick_distance
	if node is LightGun and node.scene_file_path != LIGHT_GUN_SCENE.resource_path:
		# A gun with a scene of its own -- a mod's Zapper -- is told from the
		# generic one the way a pad is: by the scene it came from.
		entry["scene"] = node.scene_file_path
	if node is RetroController:
		# Every real pad — NES, Virtual Boy, CX40 — is a RetroController with a
		# scene of its own, so the type above maps the whole family back onto the
		# generic grey pad. The scene is what tells them apart.
		entry["scene"] = node.scene_file_path
		# Which pak is in the back of this pad. Saved on the CONTROLLER for the
		# reason the Wii Remote's dongle is: the port is the end that means
		# something, and the pak's own entry is only where it is lying.
		var pak: Node = (node as RetroController).get_pak()
		if pak != null:
			entry["pak"] = _ref(node_to_id, pak)
		var vmus := _vmu_slot_refs(node, node_to_id)
		if not vmus.is_empty():
			entry["vmus"] = vmus
	return entry


## The multitap whose socket holds `peripheral`, or null.
func _multitap_holding(peripheral: Node, node_to_id: Dictionary) -> RetroMultitap:
	for node: Variant in node_to_id:
		var tap := node as RetroMultitap
		if is_instance_valid(tap) and tap.socket_of(peripheral) >= 0:
			return tap
	return null


## A multitap: the console port its plug is in (as a pad's is), its SELECT
## switch, and what is in each socket -- one reference per socket, null for an
## empty one.
func _serialize_multitap(tap: RetroMultitap, id: int, n3d: Node3D,
		node_to_id: Dictionary) -> Dictionary:
	var connected_sys: RetroSystem = tap.get_connected_system()
	var port_index := tap.get_cabinet_port()
	var sockets: Array = []
	for peripheral: Variant in tap.socket_peripherals():
		sockets.append(_ref(node_to_id, peripheral as Node))
	var entry := _base(id, "retro_multitap", n3d).merged({
		"system": _ref(node_to_id, connected_sys if port_index >= 0 else null),
		"port_index": port_index,
		"tap_mode": tap.mode,
		"sockets": sockets,
	})
	# A tap a mod dressed in a model of its own, told apart as a pad is.
	if tap.scene_file_path != RETRO_MULTITAP_SCENE.resource_path:
		entry["scene"] = tap.scene_file_path
	return entry


## The tap the entry names, or the plain one (see _instantiate_controller).
func _instantiate_multitap(data: Dictionary) -> Node3D:
	var path: String = str(data.get("scene", ""))
	if not path.is_empty() and is_known_controller_scene(path) and ResourceLoader.exists(path):
		var packed := ResourceLoader.load(path) as PackedScene
		var inst := packed.instantiate() as Node3D if packed != null else null
		if inst is RetroMultitap:
			return inst
		if inst != null:
			push_warning("[ScenePersistence] '%s' is not a multitap" % path)
			inst.queue_free()
	return RETRO_MULTITAP_SCENE.instantiate() as Node3D


## What is in each of a host's Dreamcast slots, one reference per slot and null
## for an empty one, or [] when every slot is empty.
##
## Saved on the HOST for the reason its pak is: the slot is the end that means
## something, and a card's own entry is only where it is lying. Every device
## rather than get_vmu(), which answers only for a card, so a Jump Pack is kept
## too.
func _vmu_slot_refs(host: Node, node_to_id: Dictionary) -> Array:
	if not host.has_method("get_vmu_device"):
		return []
	var out: Array = []
	var any := false
	for slot in range(int(host.call("vmu_slot_count"))):
		var device: Node = host.call("get_vmu_device", slot)
		out.append(_ref(node_to_id, device))
		any = any or device != null
	return out if any else []


## Seat a host's cards and packs back in the slots they were saved in. Before
## the host's port connection, as its pak is, so a machine is told once what is
## in the slots.
func _restore_vmu_slots(host: Node, root: Node, spawned: Dictionary, refs: Variant) -> void:
	if not (refs is Array) or not host.has_method("restore_vmu"):
		return
	var list := refs as Array
	for slot in range(list.size()):
		var device := _resolve_ref(root, spawned, list[slot]) as Node3D
		if device != null:
			host.call("restore_vmu", device, slot)


## Six independent ends, so the lead is saved as six plugs rather than as one
## object with a position: each carries its own pose and, if it is in a socket,
## the device and the socket's node name. The name is what makes this readable
## and stable — "AudioLIn" survives any renumbering of ports, which an index
## would not.
## The entry for any kind of lead, or {} for a node that is not one.
func _serialize_lead(node: Node, id: int, n3d: Node3D, node_to_id: Dictionary) -> Dictionary:
	if node is CompositeCable:
		return _serialize_cable(node as CompositeCable, id, n3d, node_to_id)
	if node is PowerCord:
		return _serialize_power_cord(node as PowerCord, id, n3d, node_to_id)
	if node is PowerStrip:
		return _serialize_power_strip(node as PowerStrip, id, n3d, node_to_id)
	if node is TravelAdapter:
		return _serialize_travel_adapter(node as TravelAdapter, id, n3d, node_to_id)
	return {}


func _serialize_cable(cable: CompositeCable, id: int, n3d: Node3D,
		node_to_id: Dictionary) -> Dictionary:
	var plugs := _plug_records(cable.seating(), node_to_id)
	var extra := {}
	# A plain lead has no body and _base's pose — the ROOT's — is the whole object.
	# The RF switch has a box the player carries while its root stays where it
	# spawned, so without this it restores at the origin and its own tether
	# immediately hauls both plugs out of their sockets to reach it.
	if cable.has_method("carried_body_pose"):
		var body_pose: Dictionary = cable.call("carried_body_pose")
		if not body_pose.is_empty():
			extra["body"] = body_pose
	if not cable.plug_color_id.is_empty():
		extra["plug_color"] = String(cable.plug_color_id)
	if cable.cord_length > 0.0:
		extra["cord_length"] = cable.cord_length
	return _base(id, "composite_cable", n3d).merged(extra).merged({
		# 2 = the mono lead, 3 = the full one. Both are CompositeCable; only
		# the scene differs, so the count is what picks it back up.
		"cords": cable.cord_count(),
		# ...except that a one-cord lead is NOT "the composite lead with a cord
		# missing" — it is a different connector entirely. Named rather than
		# inferred from the count, so the next single-cord lead to be added does not
		# silently restore as a VGA one.
		"kind": cable.scene_file_path.get_file().get_basename(),
		"plugs": plugs,
	})


## A mains lead, filed under the same entry type as an A/V one.
##
## Not because a PowerCord is a CompositeCable. It is not one: it carries no
## signal, resolves no routing, and is a fifth of the code. It is because the
## ENTRY is identical: ends with poses, and the socket each sits in named by device
## and node name. Sharing the type shares the validator, the spawn table, which
## already knew all three cord scenes by kind, and both restore passes.
##
## Nothing wrote one of these before. _serialize only recognised `is
## CompositeCable`, so a mains lead serialized to the empty entry and a saved room
## came back without it, and without any record of what had been plugged in.
func _serialize_power_cord(cord: PowerCord, id: int, n3d: Node3D,
		node_to_id: Dictionary) -> Dictionary:
	return _base(id, "composite_cable", n3d).merged({
		"cords": cord.cord_count(),
		"kind": cord.scene_file_path.get_file().get_basename(),
		"plugs": _plug_records(cord.seating(), node_to_id),
	})


## A power strip: a mains lead with a body on one end, so PowerCord's entry plus
## the body's pose — the root never moves, the player carries the Body, and without
## it the strip restores where it was first spawned. Its six sockets need nothing:
## a plug in one is recorded by THAT plug's lead, naming this strip and "SocketN".
func _serialize_power_strip(strip: PowerStrip, id: int, n3d: Node3D,
		node_to_id: Dictionary) -> Dictionary:
	var entry := _base(id, "composite_cable", n3d).merged({
		"cords": strip.cord_count(),
		"kind": strip.scene_file_path.get_file().get_basename(),
		"plugs": _plug_records(strip.seating(), node_to_id),
	})
	var body_pose := strip.carried_body_pose()
	if not body_pose.is_empty():
		entry["body"] = body_pose
	return entry


## A travel adapter: a lead that is all plug, so its plug's record is its pose.
## A plug in its socket is recorded by that plug's lead, naming it and "Socket".
func _serialize_travel_adapter(adapter: TravelAdapter, id: int, n3d: Node3D,
		node_to_id: Dictionary) -> Dictionary:
	return _base(id, "composite_cable", n3d).merged({
		"cords": adapter.cord_count(),
		"kind": adapter.scene_file_path.get_file().get_basename(),
		"plugs": _plug_records(adapter.seating(), node_to_id),
		"spliced": adapter.spliced,
	})


## One JSON record per connector, from either kind of lead's seating().
##
## The pose is the PLUG's own and global, because a lead has no meaningful body
## pose of its own: where its ends are IS where it is.
func _plug_records(seats: Array, node_to_id: Dictionary) -> Array:
	var plugs: Array = []
	for seat: Dictionary in seats:
		var plug := seat["plug"] as Node3D
		var ppos := plug.global_position
		var prot := plug.global_rotation_degrees
		plugs.append({
			"end": seat["end"],
			"cord": seat["cord"],
			"position": [ppos.x, ppos.y, ppos.z],
			"rotation": [prot.x, prot.y, prot.z],
			"port": seat["port"],
			"device": _ref(node_to_id, seat["device"] as Node),
		})
	return plugs


## Every pad scene a save or a peer may name.
##
## The `scene` field does not only come from the player's own save file: an
## object_sync snapshot carries it too, so the value can arrive from another
## machine. It used to be loaded and INSTANTIATED before the result was checked,
## which ran the named scene's scripts first and rejected it after — so any
## scene in the pack could be constructed by naming it. The allowlist moves that
## decision in front of the load.
##
## controller_scenes_are_listed in scene_tests fails if a shipped RetroController
## scene is missing here, so adding a pad cannot silently make it unrestorable.
const CONTROLLER_SCENES := [
	"res://Scenes/Objects/controllers/retro_controller.tscn",
	"res://Scenes/Objects/controllers/nes/nes_controller.tscn",
	"res://Scenes/Objects/controllers/famicom/famicom_controller_i.tscn",
	"res://Scenes/Objects/controllers/famicom/famicom_controller_ii.tscn",
	"res://Scenes/Objects/controllers/vb/vb_controller.tscn",
	"res://Scenes/Objects/controllers/atari/atari_2600_cx40.tscn",
	"res://Scenes/Objects/controllers/playstation/ps1_controller.tscn",
	"res://Scenes/Objects/controllers/playstation/ps1_dualshock.tscn",
	"res://Scenes/Objects/controllers/n64/n64_controller.tscn",
]


## True for a pad scene this build will restore: one it ships, or one a mod
## registered through register_mod_object.
static func is_known_controller_scene(path: String) -> bool:
	if CONTROLLER_SCENES.has(path):
		return true
	for type: String in _mod_objects:
		if str((_mod_objects[type] as Dictionary).get("scene", "")) == path:
			return true
	return false


## The pad scene the entry names, or the generic pad when the save predates the
## field, names a scene this build no longer ships, or names something that is
## not a controller at all. ResourceLoader.exists, not FileAccess: paths are
## remapped into the pck in an exported build.
func _instantiate_controller(data: Dictionary) -> Node3D:
	var path: String = str(data.get("scene", ""))
	if not path.is_empty() and not is_known_controller_scene(path):
		push_warning("[ScenePersistence] refusing unlisted pad scene '%s'" % path)
		path = ""
	if not path.is_empty() and ResourceLoader.exists(path):
		var packed := ResourceLoader.load(path) as PackedScene
		if packed != null:
			var inst := packed.instantiate() as Node3D
			if inst is RetroController:
				return inst
			if inst != null:
				push_warning("[ScenePersistence] '%s' is not a controller" % path)
				inst.queue_free()
	return RETRO_CONTROLLER_SCENE.instantiate() as Node3D


## The gun the entry names, or the generic one: when the entry names no scene,
## or one no enabled mod registered, or something that is not a light gun.
func _instantiate_light_gun(data: Dictionary) -> Node3D:
	var path: String = str(data.get("scene", ""))
	if not path.is_empty() and is_known_controller_scene(path) and ResourceLoader.exists(path):
		var packed := ResourceLoader.load(path) as PackedScene
		var inst := packed.instantiate() as Node3D if packed != null else null
		if inst is LightGun:
			return inst
		if inst != null:
			push_warning("[ScenePersistence] '%s' is not a light gun" % path)
			inst.queue_free()
	return LIGHT_GUN_SCENE.instantiate() as Node3D


## What a lead has to be told before it enters the tree: its plug colour and its
## cord length. Nothing for anything else.
func _restore_lead_fields(obj: Node3D, data: Dictionary) -> void:
	if obj is TravelAdapter:
		(obj as TravelAdapter).spliced = bool(data.get("spliced", false))
	if obj is CompositeCable:
		(obj as CompositeCable).plug_color_id = StringName(str(data.get("plug_color", "")))
		(obj as CompositeCable).cord_length = float(data.get("cord_length", 0.0))


## Build the object a save entry describes, before it enters the room, or null
## for an entry nothing here can make. The counterpart to serialize_node, public
## for the same callers.
func deserialize_object(data: Dictionary) -> Node3D:
	var obj := _deserialize_kind(data)
	# Its color, back on it before it enters the room.
	var variant: Variant = data.get("model_variant", "")
	if obj != null and variant is String and not (variant as String).is_empty():
		SystemModelRegistry.set_variant_of(obj, variant as String)
	return obj


func _deserialize_kind(data: Dictionary) -> Node3D:
	var obj_type: String = data.get("type", "")
	var obj: Node3D = null

	if _mod_objects.has(obj_type):
		obj = _instantiate_mod_object(obj_type)
		_restore_lead_fields(obj, data)
	elif obj_type == "light_gun":
		# Before the plain table, which has a row for it: a mod's gun is saved
		# under this type with the scene it came from.
		obj = _instantiate_light_gun(data)
	elif PLAIN_SCENES.has(obj_type):
		obj = (PLAIN_SCENES[obj_type] as PackedScene).instantiate() as Node3D
		# A Controller Pak, a VMU and an Xbox Memory Unit are PLAIN_SCENES rows so
		# the spawn menu can build one from its token, and this branch runs before
		# _LOAD_KINDS can — so their card fields are restored HERE or nowhere.
		# Identity before the tree: card_id is the card's file on disk, and one
		# that reaches _ready without it mints a fresh blank, which reads exactly
		# like the notes were wiped.
		if _PLAIN_CARD_LABELS.has(obj_type):
			_apply_card_fields(obj, data, str(_PLAIN_CARD_LABELS[obj_type]))
		# A Game Boy Printer's roll; a save from before rolls has the first.
		var printer := obj as GbPrinter
		if printer != null:
			printer.paper_roll = str(data.get("paper", ""))
	elif _LOAD_KINDS.has(obj_type):
		obj = call(_LOAD_KINDS[obj_type] as StringName, data)
	else:
		push_warning("[ScenePersistence] unknown object type '%s'" % obj_type)
		return null

	if not obj:
		return null

	var pos: Array = data.get("position", [0.0, 0.0, 0.0])
	var rot: Array = data.get("rotation", [0.0, 0.0, 0.0])
	obj.position = Vector3(pos[0], pos[1], pos[2])
	obj.rotation_degrees = Vector3(rot[0], rot[1], rot[2])
	# Float-in-place is a property of the OBJECT rather than of any one kind of
	# it, so it is applied once here instead of in a branch per device. Written
	# before the caller adds the child, which is what FloatLock needs: it reads
	# this flag in _ready and parks the body at the pose restored just above.
	if "ignore_gravity" in obj:
		obj.set("ignore_gravity", bool(data.get("ignore_gravity", false)))
	# Before the caller adds the child, so a locked object is already frozen at
	# the pose written just above and never joins the fall into place.
	if bool(data.get("locked", false)):
		ObjectLock.set_locked(obj, true)
	return obj


## The types _deserialize_kind builds by hand, each from its own `_load_<type>`:
## the load side of _save_kind_rows. A LOOKUP, unlike the save rows, because a
## type name is exact -- it was a `match`, and no two arms could both apply. Read
## after the mod objects, the light gun and PLAIN_SCENES, as the match was.
## Each builder sets what must be set BEFORE the object enters the tree; the
## pose and the flags every object shares are applied after it, in one place.
## Its keys are also every type this build loads besides PLAIN_SCENES and the mods
## (_is_known_type, register_mod_object).
const _LOAD_KINDS := {
	"system": &"_load_system",
	"tv": &"_load_tv",
	# The machines that bolt onto a console. A unit's own entry says which unit
	# it is and what is in its bay; which console it is attached to is restored
	# from the CONSOLE's entry, the way a memory card's slot is.
	"expansion": &"_load_expansion",
	"cartridge": &"_load_cartridge",
	"disc": &"_load_disc",
	"memory_card": &"_load_memory_card",
	# The lid over an expansion bay. Its own entry is just "a lid exists, here";
	# whether it is ON a console or lying where a player put it down comes from
	# that console's entry, same as the units above.
	"expansion_cover": &"_load_expansion_cover",
	# The cover over a unit's own socket (a GameCube's Serial Port 1, a fat PS2's
	# expansion bay): which socket it fits and how big it is. Whether it is on a
	# console comes from that console's "port_covers".
	"port_cover": &"_load_port_cover",
	"poster": &"_load_poster",
	"book": &"_load_book",
	"retro_controller": &"_load_retro_controller",
	# Which console port its plug is in, its SELECT switch, and the pad in each of
	# its four sockets. The pads' own entries name no port: the tap's is the end
	# that means something.
	"retro_multitap": &"_load_retro_multitap",
	"retro_mouse": &"_load_retro_mouse",
	"snes_mouse": &"_load_snes_mouse",
	"pad_receiver": &"_load_pad_receiver",
	"keyboard_receiver": &"_load_keyboard_receiver",
	"mouse_receiver": &"_load_mouse_receiver",
	"vcr_tape": &"_load_vcr_tape",
	"dvd_disc": &"_load_dvd_disc",
	"composite_cable": &"_load_composite_cable",
	"audio_disc": &"_load_audio_disc",
	"audio_cassette": &"_load_audio_cassette",
	"vinyl_record": &"_load_vinyl_record",
	# A stand a console is mounted in. Which stand it is is its own; which
	# console is in it is restored from this same entry ("console").
	"console_stand": &"_load_console_stand",
}


func _load_system(data: Dictionary) -> Node3D:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = SystemIds.canonical(str(data.get("systemid", "")))
	sys.model_id = str(data.get("model_id", ""))
	sys.model_variant = str(data.get("model_variant", ""))
	sys.pad_guid = str(data.get("pad_guid", ""))
	sys.pad_ordinal = int(data.get("pad_ordinal", 0))
	sys.core_name = str(data.get("core_name", ""))
	sys.ignore_gravity = bool(data.get("ignore_gravity", false))
	sys.cabinet_art_enabled = bool(data.get("cabinet_art", true))
	sys.attract_override = clampi(int(data.get("attract", ArcadeAttract.OVERRIDE_FOLLOW)),
		ArcadeAttract.OVERRIDE_FOLLOW, ArcadeAttract.OVERRIDE_OFF)
	if bool(data.get("attract_on", false)):
		sys.begin_attract_restore()
	sys.console_memory_id = str(data.get("console_memory", ""))
	# Before the caller adds it to the tree, like the fields above:
	# _build_expansion_hardware runs from _ready and seeds a bay's
	# default pak and its lid on a FRESH console. This save's own
	# "expansions" and "expansion_cover" are the whole truth for a
	# restored one, and a lid the player took off is recorded by
	# their ABSENCE -- so without this the seed puts a new lid back
	# on every load and nothing ever removes it.
	sys.begin_restore(
		(1 if bool(data["video_out"]) else 0) if data.has("video_out") else -1,
		float(data.get("lid_angle", -1.0)))
	return sys


func _load_tv(data: Dictionary) -> Node3D:
	var tv := TV_SCENE.instantiate() as RetroTV
	# Before the caller adds it to the tree: _load_shell runs from
	# _ready. "" is _load_shell's own "stock body, strict no-op"
	# value, so every set already in a save file restores unchanged.
	tv.tv_model = data.get("tv_model", "")
	tv.crt_enabled = data.get("crt_enabled", true)
	var crt_params: Dictionary = data.get("crt_params", {})
	if not crt_params.is_empty():
		tv.set_crt_params(crt_params)
	tv.scale_factor = data.get("scale_factor", 1.0)
	tv.stereo_mode = int(data.get("stereo_mode", 0)) as RetroTV.StereoMode
	return tv


func _load_expansion(data: Dictionary) -> Node3D:
	var unit := EXPANSION_SCENE.instantiate() as RetroExpansion
	# Before it enters the tree: RetroExpansion measures its box, its
	# connector and its bay from this id in _ready, and a unit that
	# arrives without one builds none of them.
	unit.expansion_id = str(data.get("expansion_id", ""))
	unit.rom_path = RomLibrary.relocate(str(data.get("rom_path", "")))
	unit.card_id = str(data.get("card_id", ""))
	unit.card_label = str(data.get("card_label", ""))
	return unit


func _load_cartridge(data: Dictionary) -> Node3D:
	var cart := CART_SCENE.instantiate() as RetroCartridge
	_apply_media_fields(cart, data)
	return cart


func _load_disc(data: Dictionary) -> Node3D:
	var disc_systemid := SystemIds.canonical(str(data.get("cart_systemid", "")))
	var disc_scene := UMD_DISC_SCENE if disc_systemid == "psp" else DISC_SCENE
	var disc := disc_scene.instantiate() as RetroDisc
	_apply_media_fields(disc, data)
	return disc


func _load_memory_card(data: Dictionary) -> Node3D:
	# A room saved before there were two families holds no family at
	# all, and every card in one is a PlayStation card.
	var family := str(data.get("family", "playstation"))
	var scene := MEMCARD_SCENE
	if family == "gamecube":
		scene = GC_MEMCARD_SCENE
	elif family == "playstation2":
		scene = PS2_MEMCARD_SCENE
	var card := scene.instantiate() as MemoryCard
	card.family = family
	card.card_id = data.get("card_id", "")
	card.card_label = data.get("card_label", "MEMORY CARD")
	return card


## Before it enters the tree: the stand builds its parts and its mount from
## the id in _ready. A stand nothing defines any more (its mod is gone) is
## dropped, and the console that was in it keeps its own saved pose.
func _load_console_stand(data: Dictionary) -> Node3D:
	var id := str(data.get("stand_id", ""))
	if not StandCatalog.has(id):
		push_warning("[ScenePersistence] console stand '%s' is defined by nothing installed -- skipped" % id)
		return null
	var stand := CONSOLE_STAND_SCENE.instantiate() as ConsoleStand
	stand.stand_id = id
	return stand


func _load_expansion_cover(_data: Dictionary) -> Node3D:
	return EXPANSION_COVER_SCENE.instantiate() as ExpansionCover


func _load_port_cover(data: Dictionary) -> Node3D:
	var port_cover := PORT_COVER_SCENE.instantiate() as PortCover
	port_cover.socket_id = str(data.get("cover_socket", ""))
	var cover_size: Array = data.get("cover_size", [])
	if cover_size.size() == 3:
		port_cover.size = Vector3(float(cover_size[0]), float(cover_size[1]), float(cover_size[2]))
	return port_cover


func _load_poster(data: Dictionary) -> Node3D:
	var poster := POSTER_SCENE.instantiate() as Poster
	# Size and mode BEFORE the path: the image setter derives the
	# sheet's dimensions and has to see the final scale.
	poster.size_scale = float(data.get("size_scale", 1.0))
	poster.fit_mode = int(data.get("fit_mode", 0)) as Poster.FitMode
	poster.roll_degrees = float(data.get("roll", 0.0))
	poster.image_path = str(data.get("image_path", ""))
	poster.stuck_from_save = bool(data.get("stuck", false))
	poster.printout = bool(data.get("printout", false))
	poster.sticks = bool(data.get("sticks", true))
	return poster


func _load_book(data: Dictionary) -> Node3D:
	var book := BOOK_SCENE.instantiate() as PDFBook
	book.half_page_mode = data.get("half_pages", false)
	book.size_scale = data.get("size_scale", 1.0)
	book.hardback = data.get("hardback", false)
	# A scraped manual lives under roms/<systemid>/media/, so it moves
	# with the folder exactly as a ROM does.
	book.pdf_path = RomLibrary.relocate(str(data.get("pdf_path", "")))
	# Applied after the PDF loads (stashed while _page_count == 0).
	book.set_page(int(data.get("page_state", 0)), int(data.get("page_leaf", 0)))
	return book


func _load_retro_controller(data: Dictionary) -> Node3D:
	return _instantiate_controller(data)


func _load_retro_multitap(data: Dictionary) -> Node3D:
	var tap := _instantiate_multitap(data) as RetroMultitap
	# Before _ready, which builds the switch and the device from it.
	var tap_mode := int(data.get("tap_mode", RetroMultitap.MODE_5P))
	if tap_mode == RetroMultitap.MODE_2P or tap_mode == RetroMultitap.MODE_5P:
		tap.mode = tap_mode
	return tap


func _load_retro_mouse(data: Dictionary) -> Node3D:
	var mouse := RETRO_MOUSE_SCENE.instantiate() as RetroMouse
	mouse.sensitivity = data.get("sensitivity", 2400.0)
	mouse.stick_distance = data.get("stick_distance", 0.035)
	return mouse


func _load_snes_mouse(data: Dictionary) -> Node3D:
	var snes := SNES_MOUSE_SCENE.instantiate() as SnesMouse
	snes.sensitivity = data.get("sensitivity", 2400.0)
	snes.stick_distance = data.get("stick_distance", 0.035)
	return snes


func _load_pad_receiver(data: Dictionary) -> Node3D:
	# The saved pad may well not be connected — switched off, flat, or
	# swapped for another since. That is not a failure: the receiver
	# comes back red and binds to whatever turns up
	# (PadReceiver._resolve_or_adopt), so nothing here warns about it.
	var rx := PAD_RECEIVER_SCENE.instantiate() as PadReceiver
	rx.pad_guid = data.get("pad_guid", "")
	rx.pad_name = data.get("pad_name", "")
	rx.pad_ordinal = int(data.get("pad_ordinal", 0))
	return rx


func _load_keyboard_receiver(_data: Dictionary) -> Node3D:
	return KEYBOARD_RECEIVER_SCENE.instantiate() as Node3D


func _load_mouse_receiver(_data: Dictionary) -> Node3D:
	return MOUSE_RECEIVER_SCENE.instantiate() as Node3D


func _load_vcr_tape(data: Dictionary) -> Node3D:
	var tape := TAPE_SCENE.instantiate() as VCRTape
	tape.video_path = data.get("video_path", "")
	tape.video_label = data.get("video_label", "")
	tape.tape_track = maxi(0, int(data.get("tape_track", 0)))
	tape.tape_time = maxf(0.0, float(data.get("tape_time", 0.0)))
	tape.tape_progress = clampf(float(data.get("tape_progress", 0.0)), 0.0, 1.0)
	# A room saved before tapes had cassettes keeps the one its
	# recording's header gave it as its path was set.
	if int(data.get("cassette", 0)) > 0:
		tape.cassette = int(data["cassette"])
	if float(data.get("recording_seconds", 0.0)) > 0.0:
		tape.recording_seconds = float(data["recording_seconds"])
	tape.tape_blank = maxf(0.0, float(data.get("tape_blank", 0.0)))
	return tape


func _load_dvd_disc(data: Dictionary) -> Node3D:
	var disc := DVD_DISC_SCENE.instantiate() as DVDDisc
	disc.dvd_path = data.get("dvd_path", "")
	disc.dvd_label = data.get("dvd_label", "")
	return disc


func _load_composite_cable(data: Dictionary) -> Node3D:
	var obj: Node3D = null
	# Every lead in the room is a CompositeCable; only the scene it was
	# spawned from differs. "kind" names it outright — the cord count is
	# the fallback for saves written before that field existed, and it
	# cannot tell a VGA lead from any other one-cord lead.
	var kind: String = str(data.get("kind", ""))
	# A named kind settles it. The cord-count fallback below is only
	# for saves written before the field existed, and it cannot tell a
	# VGA lead from any other one-cord lead.
	var lead: PackedScene = LEAD_SCENES.get(kind, null)
	if lead == null:
		# Two-conductor ribbon reads as a mono composite lead, which is
		# what an old save holding one would have been.
		lead = MONO_CABLE_SCENE if int(data.get("cords", 3)) == 2 						else COMPOSITE_CABLE_SCENE
	obj = lead.instantiate() as Node3D
	_restore_lead_fields(obj, data)
	return obj


func _load_audio_disc(data: Dictionary) -> Node3D:
	var adisc := AUDIO_DISC_SCENE.instantiate() as AudioDisc
	adisc.album_path = data.get("album_path", "")
	adisc.album_label = data.get("album_label", "")
	return adisc


func _load_audio_cassette(data: Dictionary) -> Node3D:
	var acass := AUDIO_CASSETTE_SCENE.instantiate() as AudioCassette
	acass.album_path = data.get("album_path", "")
	acass.album_label = data.get("album_label", "")
	acass.tape_track = maxi(0, int(data.get("tape_track", 0)))
	acass.tape_time = maxf(0.0, float(data.get("tape_time", 0.0)))
	acass.tape_progress = clampf(float(data.get("tape_progress", 0.0)), 0.0, 1.0)
	return acass


func _load_vinyl_record(data: Dictionary) -> Node3D:
	var lp := VINYL_RECORD_SCENE.instantiate() as VinylRecord
	lp.album_path = data.get("album_path", "")
	lp.album_label = data.get("album_label", "")
	return lp

## The PLAIN_SCENES types that are cards (see _card_fields), with the label each
## gets when its save names none -- what each card's own default is.
const _PLAIN_CARD_LABELS := {
	"controller_pak": "CONTROLLER PAK",
	"vmu": "VMU",
	"xbox_mu": XboxMuCard.DEFAULT_LABEL,
}


## _card_fields' way back: a card's identity from its entry, before it enters the
## tree. Duck-typed for the reason that one is.
func _apply_card_fields(card: Node, data: Dictionary, default_label: String) -> void:
	card.set("card_id", str(data.get("card_id", "")))
	card.set("card_label", str(data.get("card_label", default_label)))


func _apply_media_fields(cart: RetroCartridge, data: Dictionary) -> void:
	# A room saved before the systemids were renamed holds the old id, and a ROM
	# path through a folder that may since have been renamed with it. Read here
	# rather than by bumping VERSION, which drops the whole slot.
	cart.rom_path = RomLibrary.relocate(str(data.get("rom_path", "")))
	cart.game_label = data.get("game_label", "")
	cart.save_id = data.get("save_id", "")
	cart.systemid = SystemIds.canonical(str(data.get("cart_systemid", "")))
	cart.shell_preset = StringName(str(data.get("shell_preset", "")))
	cart.shell_color = str(data.get("shell_color", ""))
	cart.shell_flake = bool(data.get("shell_flake", false))
	cart.body_region = str(data.get("body_region", ""))
	cart.fallback_market = str(data.get("fallback_market", ""))


## The names serialize_node and deserialize_object had while they were private,
## kept because the model packs' probes (RetroXR-models/mods/probes) still call
## them by these names.
func _serialize_node(node: Node, id: int, node_to_id: Dictionary) -> Dictionary:
	return serialize_node(node, id, node_to_id)


func _deserialize_object(data: Dictionary) -> Node3D:
	return deserialize_object(data)
