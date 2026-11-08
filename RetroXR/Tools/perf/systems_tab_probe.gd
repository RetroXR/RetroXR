## Times opening the spawn menu's SPAWN > Systems tab — the multi-second stutter
## reported on Quest (2026-11-08).
##
## Replays what the player does, the way the game does it: the menu shown (host
## visible + on_menu_shown, as SpawnMenuController._show_menu), the nav switched
## away and back to SPAWN, the Games/Systems sub-tabs switched — each cold, then
## repeated. After each action it records every frame for WINDOW_FRAMES, so a
## cost that lands a frame or two later (a deferred flush, a first draw) shows.
## Then it times the pieces of the Systems grid rebuild directly.
##
## Hosted exactly as download_ui_probe hosts the menu. On a headset run it as its
## own package (preset "Quest systems tab probe", com.xenu.retroxr.stprobe — the
## probe-only export in docs/dev/quest-device.md). To measure a player's real
## setup, clone the real app's user:// and data folders into the probe package
## first (see docs/dev/testing.md, "Systems tab — perf/systems_tab_probe").
##
## Prints [perf] lines, leaves them in user://perf_result.txt, and quits.
extends Node3D

const TIMEOUT_SEC := 240.0
## Frames recorded after each action: ~2 s at 72 Hz.
const WINDOW_FRAMES := 150
const REPEATS := 3

var _lines: PackedStringArray = PackedStringArray()
var _host: Node3D = null


func _t() -> int:
	return Time.get_ticks_usec()


func _ms(a: int) -> float:
	return float(Time.get_ticks_usec() - a) / 1000.0


func _say(fmt: String, args: Array = []) -> void:
	var s: String = fmt % args if not args.is_empty() else fmt
	_lines.append(s)
	print("[perf] " + s)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Every frame of the next `n`, each on its own.
func _frame_times(n: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var last := _t()
	for i in n:
		await get_tree().process_frame
		var now := _t()
		out.append(float(now - last) / 1000.0)
		last = now
	return out


## The call's own time, then what the frames after it cost: the total over the
## idle pace, the worst frame and where it fell, and every frame over 50 ms.
func _measure(label: String, action: Callable) -> void:
	await _frames(20)
	var t := _t()
	action.call()
	var call_ms := _ms(t)
	var ft := await _frame_times(WINDOW_FRAMES)
	var worst := 0.0
	var worst_at := 0
	var over := 0.0
	var spikes := PackedStringArray()
	for i in ft.size():
		if ft[i] > worst:
			worst = ft[i]
			worst_at = i
		over += maxf(0.0, ft[i] - 14.0)
		if ft[i] > 50.0:
			spikes.append("f%d=%.0f" % [i, ft[i]])
	_say("%-34s call %8.2f ms | frames: worst %7.1f ms @f%d, over-pace total %7.1f ms  %s",
		[label, call_ms, worst, worst_at, over, " ".join(spikes)])


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SEC).timeout.connect(func() -> void:
		_say("TIMEOUT")
		_finish(1))
	_run()


func _run() -> void:
	_say("device=%s  user=%s", [OS.get_name(), OS.get_user_data_dir()])
	var menu := await _host_menu()
	if menu == null:
		_say("menu did not instantiate")
		_finish(1)
		return
	var sv: Node = menu.get("_spawn_view")
	var tabs: TabContainer = sv.get("_spawn_tabs")
	var systems_browser: Node = sv.get("_systems_browser")
	_say("systems grid: %d tiles", [(systems_browser.get("_systems") as Array).size()])

	var idle := await _frame_times(120)
	idle.sort()
	_say("idle frame p50 %.2f  max %.2f ms", [idle[idle.size() / 2], idle[idle.size() - 1]])

	# 1. Opening the menu, which lands on SPAWN > Systems. Cold first.
	for i in REPEATS:
		_hide(menu)
		await _frames(30)
		await _measure("open menu (Spawn>Systems) #%d" % (i + 1), _show.bind(menu))

	# 2. Nav: OPTIONS, then back to SPAWN.
	for i in REPEATS:
		await _measure("nav -> Options #%d" % (i + 1), menu.call.bind("_show_options_view"))
		await _measure("nav -> Spawn #%d" % (i + 1), menu.call.bind("_show_spawn_view"))

	# 3. Sub-tabs: Games, then back to Systems.
	var systems_idx := _tab_index(tabs, "Systems")
	var games_idx := _tab_index(tabs, "Games")
	for i in REPEATS:
		await _measure("sub-tab -> Games #%d" % (i + 1), tabs.set.bind("current_tab", games_idx))
		await _measure("sub-tab -> Systems #%d" % (i + 1), tabs.set.bind("current_tab", systems_idx))

	# 4. The rebuild that a tab show pays when something is owed, in pieces.
	_breakdown(sv)
	await _measure("_populate_systems_tab", sv.call.bind("_populate_systems_tab"))
	await _measure("_populate_cartridges_tab", sv.call.bind("_populate_cartridges_tab"))
	await _measure("on_menu_shown (menu open)", menu.call.bind("on_menu_shown"))

	_say("---- done ----")
	_finish(0)


func _breakdown(sv: Node) -> void:
	var core_defaults: Variant = sv.get("core_defaults")
	var t := _t()
	var defaults: Array = (core_defaults.all_defaults() as Dictionary).keys()
	_say("  core_defaults.all_defaults      %8.2f ms  (%d)", [_ms(t), defaults.size()])
	t = _t()
	var names: Array = sv.call("_installed_core_names")
	_say("  _installed_core_names           %8.2f ms  (%d)", [_ms(t), names.size()])
	var seen: Dictionary = {}
	for sid: String in defaults:
		seen[sid] = true
	t = _t()
	var extra: Array = sv.call("_extra_systemids", seen)
	_say("  _extra_systemids                %8.2f ms  (%d)", [_ms(t), extra.size()])
	var ids: Array = defaults + extra
	t = _t()
	var slowest := ""
	var slowest_ms := 0.0
	for sid: String in ids:
		var t1 := _t()
		SpawnCatalog.items_for(sid)
		var m := _ms(t1)
		if m > slowest_ms:
			slowest_ms = m
			slowest = sid
	_say("  SpawnCatalog.items_for x%d      %8.2f ms  (slowest %s %.2f ms)",
		[ids.size(), _ms(t), slowest, slowest_ms])
	t = _t()
	for sid: String in ids:
		sv.get("core_db").get_systemname_for_id(sid)
	_say("  get_systemname_for_id x%d       %8.2f ms", [ids.size(), _ms(t)])


func _tab_index(tabs: TabContainer, title: String) -> int:
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i) == title:
			return i
	return 0


## SpawnMenuController._show_menu / _hide_menu, minus placement and the HUD.
func _show(menu: Node) -> void:
	_host.visible = true
	menu.call("on_menu_shown")


func _hide(menu: Node) -> void:
	_host.visible = false
	menu.call("on_menu_hidden")


func _finish(code: int) -> void:
	var f := FileAccess.open("user://perf_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	get_tree().quit(code)


## player_rig.tscn's SpawnMenuViewport, rebuilt: same host, size and panel.
func _host_menu() -> Control:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 1.3)
	add_child(cam)
	cam.make_current()

	var host := (load("res://addons/godot-xr-tools/objects/viewport_2d_in_3d.tscn") \
		as PackedScene).instantiate() as XRToolsViewport2DIn3D
	host.name = "SpawnMenuViewport"
	host.screen_size = Vector2(1.1, 0.9)
	host.scene = load("res://Scenes/UI/spawn_menu.tscn") as PackedScene
	host.viewport_size = Vector2(2200, 1800)
	host.transparent = XRToolsViewport2DIn3D.TransparancyMode.TRANSPARENT
	host.unshaded = true
	var curve := CurvedPanel.new()
	curve.name = "CurvedPanel"
	host.add_child(curve)
	_host = host

	var t := _t()
	add_child(host)
	var menu := host.get_scene_instance() as Control
	_say("menu instantiate (sync)          %8.2f ms", [_ms(t)])
	var ft := await _frame_times(60)
	var worst := 0.0
	for f: float in ft:
		worst = maxf(worst, f)
	_say("menu first 60 frames             worst %.1f ms", [worst])
	return menu
