## mods_apply_probe — the Installed page's button, in the REAL app: Apply now
## loads a mod into the room being stood in, and Restart now relaunches the app
## into the same room. No suite can show either: the room has to be built, the
## menu drawn, and in the second case the process has to die and come back.
##
##   APPDATA=<scratch>/appdata USERPROFILE=<scratch>/home \
##     godot --path RetroXR --resolution 1280x720 --position 20,20 \
##     res://Tools/mods/mods_apply_probe.tscn [-- --mod=xenu.panasonic]
##
## WINDOWED, and only against a SCRATCH home and a scratch user:// -- it switches
## mods on and off, writes the prefs and restarts the app. It refuses to run
## unless both hold a file named probe_home.txt, which a player's never do:
##   <scratch>/home/retroxr/probe_home.txt
##   <scratch>/appdata/Godot/app_userdata/RetroXR/probe_home.txt
## and the mod (default xenu.panasonic, a TV cabinet that claims no shipped file)
## must be in <scratch>/home/retroxr/mods/, switched OFF.
##
## Boots the game as BootScene does, furnishes the room, steps the player aside,
## then presses Apply now and checks the room came back as it stood, with the
## player where they were and the mod's cabinet on the TVs tab -- and spawns one.
## Then switches the mod off and presses Restart now. The app relaunches into this
## same probe (its scene is on the command line), which sees phase 2 in its own
## file and checks the room was carried across the restart. It never restarts
## from phase 2, so a broken check cannot relaunch it for ever.
##
## PNGs and result.txt go to user://mods_apply_probe/ (the scratch one).
extends Node

const OUT := "user://mods_apply_probe"
const MARKER := "probe_home.txt"


func _ready() -> void:
	var driver := Driver.new()
	driver.name = "ModsApplyProbe"
	get_tree().root.add_child.call_deferred(driver)
	get_tree().change_scene_to_file.call_deferred("res://Scenes/BootScene.tscn")


## Lives on the root, beside the room, so the scene swaps leave it alone.
class Driver extends Node:
	var _mod := "xenu.panasonic"
	var _lines: PackedStringArray = []
	var _failed := 0

	func _ready() -> void:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--mod="):
				_mod = a.substr(6)
		get_tree().create_timer(150.0).timeout.connect(func() -> void:
			_say("TIMEOUT")
			_finish(1))
		if not FileAccess.file_exists(DataPaths.media_root(MARKER)) \
				or not FileAccess.file_exists("user://" + MARKER):
			push_error("[probe] not a scratch home and user dir: refusing")
			get_tree().quit(2)
			return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
		var phase := FileAccess.get_file_as_string(OUT.path_join("phase.txt")).strip_edges()
		await _settled()
		if phase == "2":
			await _phase_two()
		else:
			await _phase_one()

	# ── phase 1: Apply now, then Restart now ──────────────────────────────────

	func _phase_one() -> void:
		var room := get_tree().current_scene
		_say("phase 1 in %s (data root %s)" % [SceneManager.current_scene_id, DataPaths.media_root()])
		var rec := Mods.mod(_mod)
		if not _ok(rec != null and rec.status == ModRecord.Status.DISABLED and not rec.loaded,
				"the mod is installed and switched off"):
			_finish(1)
			return

		# Furnish: two consoles on the floor in front of the player and a stock TV
		# behind them, as a saved room would put them. (A set spawned from the menu
		# hangs FROZEN where it appeared until it is grabbed, and `freeze` is not
		# saved -- ScenePersistence._hold_still says why -- so any save and restore
		# puts that one on the floor. Not the carry's to fix, so not used here.)
		var cam := get_viewport().get_camera_3d()
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := fwd.cross(Vector3.UP)
		var base := cam.global_position + fwd * 1.6
		var entries := []
		for i in 2:
			var at := base + right * (-0.35 + 0.7 * i)
			entries.append({"id": i, "type": "system", "systemid": ["nes", "snes"][i],
				"position": [at.x, 0.3, at.z], "rotation": [0, 0, 0]})
		var tv_at := base + fwd * 0.5
		var yaw := rad_to_deg(atan2(-fwd.x, -fwd.z)) + 180.0
		entries.append({"id": 2, "type": "tv", "position": [tv_at.x, 0.4, tv_at.z],
			"rotation": [0, yaw, 0]})
		ScenePersistence.new(SceneManager.current_scene_id).instantiate_objects(room, entries)
		var controller := _controller()
		# Look down at them; on a desktop nothing else moves the camera.
		cam.rotation.x = deg_to_rad(-28.0)
		# Step aside, so a reload that put the player back at the door would show.
		var rig := room.get_node("PlayerRig") as PlayerRig
		rig.origin.position += Vector3(0.35, 0.0, 0.2)
		await _wait(3.0)
		var before := _population()
		var origin_before := rig.origin.global_position
		_say("before: %s" % [before])
		await _shot("1_room_before")

		# The page, with the mod switched on: the banner offers Apply now.
		var menu: SpawnMenu2D = controller._get_menu()
		controller._show_menu()
		menu._show_mods_view()
		var view := menu._mods_view
		view._tabs.current_tab = SpawnMenuModsView.INSTALLED_TAB
		Mods.set_enabled(_mod, true)
		view.refresh_installed()
		await _wait(0.8)
		var apply := _banner_button(view)
		_ok(apply != null and apply.text == "Apply now" and not apply.disabled,
			"the banner offers Apply now")
		await _shot("2_banner_apply")
		await _menu_shot(controller, "2_banner_apply_menu")
		if apply == null:
			_finish(1)
			return

		apply.pressed.emit()
		await _settled(true)
		await _wait(3.0)
		var after := _population()
		_say("after: %s" % [after])
		_ok(rec.status == ModRecord.Status.LOADED and rec.loaded, "the mod is loaded, no restart")
		_eq(after.size(), before.size(), "the room came back with as many things in it")
		_ok(_same_places(before, after), "and each where it stood")
		_ok(rig.origin.global_position.distance_to(origin_before) < 0.01,
			"the player is where they stood (moved %.3f m)" % rig.origin.global_position.distance_to(origin_before))
		_ok(not controller._viewport_node.visible, "the menu closed for the reload")
		var shell := ""
		for s: Dictionary in RetroTV.mod_shells():
			if str(s["id"]).begins_with(_mod + ":"):
				shell = str(s["id"])
		_ok(not shell.is_empty(), "its cabinet is registered: %s" % shell)
		var labels: Array = []
		for child: Node in menu.spawn_view()._tvs_vbox.get_children():
			if child is Button and not child.is_queued_for_deletion():
				labels.append((child as Button).text.strip_edges())
		_ok(labels.size() >= 3, "and on the TVs tab: %s" % [labels])
		_ok(not FileAccess.file_exists("user://scenes/%s/_carry.json" % SceneManager.current_scene_id),
			"the carry was used up")
		await _shot("3_room_after_apply")
		if not shell.is_empty():
			controller._on_spawn_requested("tv:" + shell)
			await _wait(3.0)
			await _shot("4_mod_tv_spawned")

		# Off again: a running pack cannot be unmounted, so the button restarts.
		controller._show_menu()
		menu._show_mods_view()
		view._tabs.current_tab = SpawnMenuModsView.INSTALLED_TAB
		Mods.set_enabled(_mod, false)
		view.refresh_installed()
		await _wait(0.8)
		var restart := _banner_button(view)
		_ok(restart != null and restart.text == "Restart now" and not restart.disabled,
			"switched off, the banner offers Restart now")
		await _menu_shot(controller, "5_banner_restart_menu")
		var expect := _population()
		_write("phase.txt", "2")
		_write("expect.json", JSON.stringify(expect))
		_write("result1.txt", "\n".join(_lines) + "\n%d FAILED\n" % _failed)
		if _failed > 0 or restart == null:
			_finish(1)
			return
		print("[probe] pressing Restart now; phase 2 reports in result2.txt")
		restart.pressed.emit()

	# ── phase 2: back after the restart ───────────────────────────────────────

	func _phase_two() -> void:
		_write("phase.txt", "done")
		_say("phase 2 in %s, pid %d" % [SceneManager.current_scene_id, OS.get_process_id()])
		await _wait(3.0)
		var rec := Mods.mod(_mod)
		_ok(rec != null and rec.status == ModRecord.Status.DISABLED and not rec.loaded,
			"after the restart the mod is off")
		var expect: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("expect.json")))
		var now := _population()
		_say("now: %s" % [now])
		var systems := now.filter(func(o: Dictionary) -> bool: return o["kind"] == "system")
		_eq(systems.size(), 2, "both consoles were carried across the restart")
		_ok(_same_places((expect as Array).filter(func(o: Dictionary) -> bool:
			return o["kind"] == "system"), systems), "where they stood")
		_ok(now.size() >= 3, "and the TVs (%d things)" % now.size())
		_eq(SceneManager._carry_room_id, "", "the carry mark is spent")
		# A new process stands at the room's entrance, as any launch does; stand
		# and look where phase 1 did, so the two pictures line up.
		var rig := get_tree().current_scene.get_node("PlayerRig") as PlayerRig
		rig.origin.position += Vector3(0.35, 0.0, 0.2)
		get_viewport().get_camera_3d().rotation.x = deg_to_rad(-28.0)
		await _wait(1.0)
		await _shot("6_room_after_restart")
		_write("result2.txt", "\n".join(_lines) + "\n%d FAILED\n" % _failed)
		_finish(0 if _failed == 0 else 1)

	# ── helpers ───────────────────────────────────────────────────────────────

	## Wait for the room to have finished arriving -- or, with `change`, for it
	## to go away and arrive again.
	func _settled(change := false) -> void:
		if change:
			var t := 0
			while SceneManager.is_scene_content_ready(SceneManager.current_scene_id) and t < 600:
				await get_tree().process_frame
				t += 1
		while not SceneManager.is_scene_content_ready(SceneManager.current_scene_id):
			await get_tree().process_frame
		await _wait(1.0)

	func _wait(sec: float) -> void:
		await get_tree().create_timer(sec).timeout

	func _controller() -> Node:
		for n: Node in get_tree().root.find_children("*", "Node3D", true, false):
			var s: Script = n.get_script()
			if s != null and s.resource_path.ends_with("spawn_menu_controller.gd"):
				return n
		return null

	func _banner_button(view: SpawnMenuModsView) -> Button:
		for child: Node in view._installed_banner.find_children("*", "Button", true, false):
			if not child.is_queued_for_deletion():
				return child as Button
		return null

	## What is in the room, by kind and place.
	func _population() -> Array:
		var out := []
		for n: Node in get_tree().get_nodes_in_group("spawned"):
			var kind := ""
			if n is RetroSystem:
				kind = "system"
			elif n is RetroTV:
				kind = "tv"
			else:
				continue
			var p := (n as Node3D).global_position
			out.append({"kind": kind, "name": str(n.name), "at": [snappedf(p.x, 0.01),
				snappedf(p.y, 0.01), snappedf(p.z, 0.01)]})
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["kind"]) + str(a["at"]) < str(b["kind"]) + str(b["at"]))
		return out

	func _same_places(a: Array, b: Array) -> bool:
		if a.size() != b.size():
			return false
		for i in a.size():
			var pa := Vector3(a[i]["at"][0], a[i]["at"][1], a[i]["at"][2])
			var pb := Vector3(b[i]["at"][0], b[i]["at"][1], b[i]["at"][2])
			if a[i]["kind"] != b[i]["kind"] or pa.distance_to(pb) > 0.05:
				return false
		return true

	func _shot(name: String) -> void:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT.path_join(name + ".png")))
		_say("wrote %s.png %s" % [name, img.get_size()])

	func _menu_shot(controller: Node, name: String) -> void:
		var vp := controller._viewport_node.get_node_or_null("Viewport") as SubViewport
		if vp == null:
			return
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(
			ProjectSettings.globalize_path(OUT.path_join(name + ".png")))
		_say("wrote %s.png" % name)

	func _ok(cond: bool, what: String) -> bool:
		if not cond:
			_failed += 1
		_say(("ok   " if cond else "FAIL ") + what)
		return cond

	func _eq(got: Variant, want: Variant, what: String) -> void:
		_ok(got == want, what if got == want else "%s (got %s, want %s)" % [what, got, want])

	func _say(line: String) -> void:
		_lines.append(line)
		print("[probe] ", line)

	func _write(file: String, text: String) -> void:
		var f := FileAccess.open(OUT.path_join(file), FileAccess.WRITE)
		if f != null:
			f.store_string(text)

	func _finish(code: int) -> void:
		print("[probe] %d failed" % _failed)
		get_tree().quit(code)
