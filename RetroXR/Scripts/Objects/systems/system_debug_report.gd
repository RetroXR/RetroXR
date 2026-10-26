## SystemDebugReport — the Debug tab of a machine's menu: what the running core
## reports about itself, as sections of [label, value] rows:
## [[section, [[label, value], ...]], ...].
##
## Lifted out of system.gd whole. It is a report and nothing else: it reads the
## machine's public surface (its Libretro node, the resolved core, the option
## counts) and writes nothing, so it is static and holds no state of its own.
## RetroSystem.debug_state() is the name the menu calls; this is its body.
class_name SystemDebugReport
extends RefCounted


## Every value is read, never reset. GetPacingStats is left out on purpose: it
## hands over its worst frame and zeroes it, so a menu polling it would steal the
## number pace_trace and the link probes are waiting for. And nothing is asked of
## the core until GetCoreIdentity answers — it is the one getter that checks the
## core is there, and most of the others dereference it unguarded.
static func rows(host: RetroSystem) -> Array:
	var core := host.resolve_core_name()
	var lib := host.get_libretro_node()
	var machine: Array = [
		["Power", "On" if host.is_powered_on else "Off"],
		["Core", core if not core.is_empty() else "(none resolved)"],
		["Content", host.rom_path.get_file() if not host.rom_path.is_empty() else "(none)"],
		["HW render requested", AppPrefs.hw_render_for(core)],
	]
	var out: Array = [["Machine", machine]]
	var ident: Dictionary = lib.GetCoreIdentity() if lib != null else {}
	if not host.is_powered_on or ident.is_empty():
		machine.append(["", "Start a game to see the core's numbers"])
		return out

	# What the core declared, from the extension's own snapshot (taken on the
	# emulation thread). Asked only when the extension has it: one built before
	# it -- the Quest's, if only windows was rebuilt -- would say "Nonexistent
	# function" the first time this tab opened, and that is how a stale build once
	# shipped. RetroSystem.stale_libretro_methods() has already said so loudly at boot.
	var info: Dictionary = {}
	if not RetroSystem.stale_libretro_methods().has("GetCoreDebugInfo"):
		info = lib.GetCoreDebugInfo()

	var size := int(ident.get("serialize_size", 0))
	var core_rows: Array = [
		["Library", "%s %s" % [ident.get("library_name", "?"), ident.get("library_version", "")]],
		["libretro API", str(ident.get("api_version", "?"))],
		["Savestate size", "not measured yet" if size <= 0 else ByteSize.human(size)],
	]
	if not info.is_empty():
		core_rows.append_array([
			["Extensions", str(info.get("valid_extensions", ""))],
			["Needs full path", _yes_no(info.get("need_fullpath", false))],
			["Blocks extraction", _yes_no(info.get("block_extract", false))],
			["Performance level", str(info.get("performance_level", 0))],
			["Options API", ["SET_VARIABLES (v0)", "SET_CORE_OPTIONS (v1)",
				"SET_CORE_OPTIONS_V2"][int(info["options_api"])]
				if int(info.get("options_api", -1)) >= 0 else "none"],
		])
		var subs: PackedStringArray = info.get("subsystems", PackedStringArray())
		if not subs.is_empty():
			core_rows.append(["Subsystems", ", ".join(subs)])
	out.append(["Core", core_rows])

	var g: Dictionary = lib.GetVideoGeometry()
	var frames := int(lib.GetFrameCount())
	out.append(["Video", [
		["Frame", "%d × %d" % [int(g.get("width", 0)), int(g.get("height", 0))]],
		["Base", "%d × %d" % [int(g.get("base_width", 0)), int(g.get("base_height", 0))]],
		["Display aspect", "%.4f (core says %.4f)" % [float(g.get("aspect", 0.0)),
			float(g.get("core_aspect", 0.0))]],
		["Rotation", "%d°" % (int(g.get("rotation", 0)) * 90)],
		["Declared FPS", "%.3f" % float(lib.GetDeclaredFps())],
		["Frames run", str(frames)],
		["Frames dropped", str(int(lib.GetDroppedFrameCount()))],
	]])
	if not info.is_empty():
		var hw := int(info.get("hw_context", 0))
		var api := str(HW_CONTEXT_NAMES.get(hw, "type %d" % hw))
		if hw != 0 and int(info.get("hw_version_major", 0)) > 0:
			api += " %d.%d" % [int(info["hw_version_major"]), int(info.get("hw_version_minor", 0))]
		(out[-1][1] as Array).append_array([
			["Max", "%d × %d" % [int(info.get("max_width", 0)), int(info.get("max_height", 0))]],
			["Pixel format", str(PIXEL_FORMAT_NAMES.get(int(info.get("pixel_format", -1)), "?"))
				if hw == 0 else "(hardware rendered)"],
			["Renderer", api],
			["Shared context", _yes_no(info.get("shared_context", false))],
		])
	var transfer: Dictionary = lib.GetVideoTransferStats()
	if bool(transfer.get("enabled", false)):
		var up: Dictionary = transfer.get("texture_update", {})
		var calls := maxi(int(up.get("calls", 0)), 1)
		(out[-1][1] as Array).append(["Texture upload", "%.2f ms avg, %.2f worst" % [
			float(up.get("total_ms", 0.0)) / calls, float(up.get("max_ms", 0.0))]])

	var rate := float(lib.GetDeclaredSampleRate())
	out.append(["Audio", [
		["Declared sample rate", "%.1f Hz" % rate],
		["Buffered", "%d frames (%.1f ms)" % [int(lib.GetAudioBufferOccupancy()),
			1000.0 * lib.GetAudioBufferOccupancy() / rate if rate > 0.0 else 0.0]],
		["Pacing brake", "%.1f ms" % float(lib.GetAudioBrakeMs())],
		["Microphone", "listening" if lib.IsMicrophoneActive() else "off"],
	]])
	if not info.is_empty():
		(out[-1][1] as Array).append_array([
			["Buffer status callback", _yes_no(info.get("audio_status_callback", false))],
			["Minimum latency asked", "%d ms" % int(info.get("min_audio_latency_ms", 0))
				if int(info.get("min_audio_latency_ms", 0)) > 0 else "none"],
		])

		out.append(["Timing", [
			["Core frame time", "%.2f ms avg, %.2f worst (last second)" % [
				float(info.get("run_avg_ms", 0.0)), float(info.get("run_worst_ms", 0.0))]],
			["av_info FPS / rate", "%.3f / %.1f Hz" % [float(info.get("av_fps", 0.0)),
				float(info.get("av_sample_rate", 0.0))]],
		]])

		out.append(["Memory", [
			["Save RAM", _bytes_or_none(int(info.get("save_ram", 0)))],
			["RTC", _bytes_or_none(int(info.get("rtc", 0)))],
			["System RAM", _bytes_or_none(int(info.get("system_ram", 0)))],
			["Video RAM", _bytes_or_none(int(info.get("video_ram", 0)))],
			["Memory map descriptors", str(int(info.get("memory_descriptors", 0)))],
		]])

		var disk := int(info.get("disk_control", 0))
		var ports: Dictionary = info.get("port_devices", {})
		var port_words := PackedStringArray()
		var port_keys := ports.keys()
		port_keys.sort()
		for p: int in port_keys:
			port_words.append("%d: %s" % [p + 1, _device_word(int(ports[p]))])
		out.append(["Input & media", [
			["Port devices", ", ".join(port_words) if not port_words.is_empty() else "(defaults)"],
			["Input descriptors", str(int(info.get("input_descriptors", 0)))],
			["Controller info ports", str(int(info.get("controller_info_ports", 0)))],
			["Disk control", "none" if disk == 0 else "%s, disk %d of %d" % [
				"extended" if disk == 2 else "original",
				int(info.get("disk_index", 0)) + 1, int(info.get("disk_count", 0))]],
		]])

	var other: Array = [
		["Camera", "running" if lib.IsCameraActive() else "off"],
		["Core options", "%d set, %d pinned" % [host.core_option_values().size(),
			host.forced_core_options().size()]],
	]
	if NetworkManager.is_active():
		other.append(["Netplay rollbacks", str(int(lib.GetNetplayRollbackCount()))])
	if not info.is_empty():
		other.append(["Achievements", "supported" if bool(info.get("supports_achievements", true))
			else "core opts out"])
	# The rcheevos session is one at a time; its game is only this machine's
	# while this machine holds it.
	if RA.session_owner() == host:
		var game: Dictionary = RA.game_info()
		if not game.is_empty():
			other.append(["RetroAchievements game", "%s (id %s, hash %s)" % [
				game.get("title", "?"), game.get("id", "?"), game.get("hash", "?")]])
	out.append(["Other", other])
	return out


## libretro.h's retro_pixel_format and retro_hw_context_type, for the Debug tab.
const PIXEL_FORMAT_NAMES := {0: "0RGB1555", 1: "XRGB8888", 2: "RGB565"}
const HW_CONTEXT_NAMES := {0: "Software", 1: "OpenGL", 2: "OpenGL ES 2",
	3: "OpenGL core", 4: "OpenGL ES 3", 5: "OpenGL ES (versioned)", 6: "Vulkan",
	7: "Direct3D 11", 8: "Direct3D 10", 9: "Direct3D 12", 10: "Direct3D 9"}
## RETRO_DEVICE_* base types; a core's own subclass is base | (n + 1) << 8.
const DEVICE_NAMES := {0: "none", 1: "joypad", 2: "mouse", 3: "keyboard",
	4: "lightgun", 5: "analog", 6: "pointer"}


static func _yes_no(v: Variant) -> String:
	return "yes" if bool(v) else "no"


static func _bytes_or_none(n: int) -> String:
	return "none" if n <= 0 else "%s (%d bytes)" % [ByteSize.human(n), n]


static func _device_word(id: int) -> String:
	var base := str(DEVICE_NAMES.get(id & 0xff, "device %d" % (id & 0xff)))
	return base if id >> 8 == 0 else "%s #%d" % [base, (id >> 8) - 1]
