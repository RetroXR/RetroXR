extends Node

## Photographs an options panel's 2D UI at the real viewport size the 3D panel uses:
## the aerial's menu (tuner box + channel list), or the television's.
##
##   godot --path RetroXR --resolution 640x520 --position 20,20 \
##     res://Tools/av/tv_panel_probe.tscn -- --ui=antenna [--offline]
##   godot --path RetroXR --resolution 640x520 --position 20,20 \
##     res://Tools/av/tv_panel_probe.tscn -- --ui=tv --tab=1
##
## --ui=antenna  AntennaOptions2D, fed by a real TVLineup: it waits for DISCOVERY so
##               the status line and the 80-odd broadcast rows are the real ones.
##     --offline skips the network and fills the list with a sample lineup, for a
##               machine with no HDHomeRun on the LAN. The layout is what it proves.
##     --loose   photographs it as it reads with the lead plugged into nothing.
## --ui=tv       TVOptions2D, which no longer has a Channels tab (--tab=0 Options,
##               1 CRT). The list moved to the aerial with the thing it describes.
##
## PNG lands in res://probe_out/<ui>_panel.png (gitignored).

const TV_UI := preload("res://Scenes/UI/tv_options_2d.tscn")
const ANTENNA_UI := preload("res://Scenes/UI/antenna_options_2d.tscn")

const SAMPLE := [
	["2.1", "KATU-HD", true], ["2.2", "MeTV", false], ["6.1", "KOIN-HD", true],
	["8.1", "KGW-HD", true], ["10.1", "OPB-HD", true], ["10.2", "OPB Kids", false],
	["12.1", "KPTV-HD", true], ["24.1", "KNMT", false], ["32.1", "KRCW-HD", true],
	["49.1", "KPDX-HD", true],
]

var _sv: SubViewport = null
var _which := "antenna"
var _tab := 0
var _offline := false
var _loose := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui="):
			_which = arg.split("=")[1]
		elif arg.begins_with("--tab="):
			_tab = int(arg.split("=")[1])
		elif arg == "--offline":
			_offline = true
		elif arg == "--loose":
			_loose = true
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[panel] TIMEOUT")
		get_tree().quit(1))
	await _run()


func _run() -> void:
	_sv = SubViewport.new()
	# The size both panel scenes give their viewport.
	_sv.size = Vector2i(550, 500)
	_sv.transparent_bg = false
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)

	if _which == "tv":
		await _show_tv()
	else:
		await _show_antenna()

	for f in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute("res://probe_out")
	var out := "res://probe_out/%s_panel.png" % _which
	_sv.get_texture().get_image().save_png(out)
	print("[panel] saved %s" % out)
	get_tree().quit(0)


func _show_antenna() -> void:
	var ui := ANTENNA_UI.instantiate() as AntennaOptions2D
	_sv.add_child(ui)
	await get_tree().process_frame
	await get_tree().process_frame

	var channels: Array = []
	var status := "HDHomeRun FLEX 4K — 192.168.0.100 — 4 tuner(s) — %d channels" % SAMPLE.size()
	var host := "192.168.0.100"
	var auto := true
	if _offline:
		for row: Array in SAMPLE:
			channels.append({"number": row[0], "name": row[1], "hd": row[2],
				"url": "", "source": "hdhomerun"})
	else:
		# A real lineup, so the list is the real 80-odd broadcast rows.
		var lineup := TVLineup.new()
		add_child(lineup)
		lineup.reload_channels()
		# Wait for DISCOVERY, not just for channels: the cache fills the list within
		# a frame, and populating then would photograph "Looking for a tuner…" and
		# prove nothing about the status line.
		print("[panel] waiting for discovery…")
		var deadline := Time.get_ticks_msec() + 25000
		while lineup.discovered_host().is_empty() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		channels = lineup.channels
		status = lineup.tuner_status_line()
		host = lineup.discovered_host()
		auto = lineup.tuner_auto()

	ui.populate_link("" if _loose else "TV", false)
	ui.populate_channels(channels, -1 if _loose else mini(3, channels.size() - 1))
	ui.populate_tuner(auto, host, host, status)
	print("[panel] antenna: %d channels; status: %s" % [channels.size(), status])


func _show_tv() -> void:
	var ui := TV_UI.instantiate() as TVOptions2D
	_sv.add_child(ui)
	await get_tree().process_frame
	await get_tree().process_frame
	ui.populate(1.0)
	var tabs := _find_tabs(ui)
	if tabs:
		tabs.current_tab = clampi(_tab, 0, tabs.get_tab_count() - 1)
		print("[panel] tv tabs: %s (showing %d)"
			% [str(range(tabs.get_tab_count()).map(func(i: int) -> String:
				return tabs.get_tab_title(i))), tabs.current_tab])


func _find_tabs(n: Node) -> TabContainer:
	if n is TabContainer:
		return n as TabContainer
	for c in n.get_children():
		var found := _find_tabs(c)
		if found:
			return found
	return null
