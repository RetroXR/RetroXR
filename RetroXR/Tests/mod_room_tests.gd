## mod_room_tests — what a room a mod registers needs from the game around it.
##
## ModApi.register_room put a room in RoomCatalog and nothing more: the SCENE tab
## had cards for the shipped rooms only, a mod room's slots went to a folder named
## after its "<mod>:<name>" id, which Windows refuses, and a wall switch could only
## drive the shipped rooms' own lamps. One group each, run against throwaway rooms
## registered here and dropped at the end; no slot of the player's is touched.
##
##   "$godot" --headless --path RetroXR res://Tests/mod_room_tests.tscn
extends "res://Tests/test_suite.gd"

const EXPECTED_CASES := 28

const OWNER := "t.modroom"
const SLOT_ROOM := "t.modroom:attic"
const PLAIN_ROOM := "t.modroom:hall"
## Any scene that exists does; register_mod_room only checks the path loads.
const SCENE := "res://Scenes/DenScene.tscn"


## A lamp a GROUP gang drives: anything with set_lit().
class Lamp extends Node:
	var lit := false
	var calls := 0

	func set_lit(on: bool) -> void:
		lit = on
		calls += 1


func _ready() -> void:
	suite_tag = "modroom"
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		push_error("[modroom] TIMEOUT")
		get_tree().quit(1))

	_group_slot_dir()
	_group_switch()
	_group_scene_tab()

	RoomCatalog.drop_mod(OWNER)
	_eq(_case_count(), EXPECTED_CASES, "suite/every case ran")
	_finish()


# ── slots/ ────────────────────────────────────────────────────────────────────

func _group_slot_dir() -> void:
	# The shipped rooms' folders must not move: players' slots live in them.
	for room: String in ["arcade", "bedroom", "passthrough"]:
		_eq(ScenePersistence.new(room).slot_dir(), "user://scenes/" + room,
			"slots/%s folder unchanged" % room)

	var store := ScenePersistence.new(SLOT_ROOM)
	var dir := store.slot_dir()
	var folder := dir.get_file()
	_ok(not folder.contains(":"), "slots/a mod room's folder has no ':'", folder)
	_eq(folder.uri_decode(), SLOT_ROOM, "slots/the folder decodes to the room id")
	_eq(dir.get_base_dir(), ScenePersistence.ROOMS_DIR, "slots/it is one level under the rooms dir")

	# The failure this fixes was on disk, so prove the disk takes it.
	_eq(DirAccess.make_dir_recursive_absolute(dir), OK, "slots/the folder can be created")
	var f := FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE)
	_ok(f != null, "slots/a manifest can be written in it",
		"open error %d" % FileAccess.get_open_error())
	if f != null:
		f.store_string(JSON.stringify({"version": ScenePersistence.VERSION, "slots": []}))
		f.close()
	_eq(str(store.get_slots()[0].get("id", "")), "clean", "slots/a fresh mod room lists Clean first")
	DirAccess.remove_absolute(dir.path_join("manifest.json"))
	DirAccess.remove_absolute(dir)
	_ok(not DirAccess.dir_exists_absolute(dir), "slots/scratch folder removed")


# ── switch/ ───────────────────────────────────────────────────────────────────

func _group_switch() -> void:
	var holder := Node3D.new()
	add_child(holder)

	var lamp := Lamp.new()
	lamp.add_to_group(&"t_modroom_lamps")
	holder.add_child(lamp)
	# In the group but with no set_lit(): skipped, not an error.
	var mute := Node.new()
	mute.add_to_group(&"t_modroom_lamps")
	holder.add_child(mute)
	# A shipped ceiling lamp, which a GROUP gang must leave alone.
	var ceiling := OmniLight3D.new()
	ceiling.add_to_group(&"ceiling_light")
	holder.add_child(ceiling)

	var sw := LightSwitch.new()
	sw.target = LightSwitch.Target.GROUP
	sw.group = &"t_modroom_lamps"
	holder.add_child(sw)

	sw.set_lights_on(true)
	_ok(lamp.lit, "switch/on reaches a lamp in its group")
	sw.set_lights_on(false)
	_ok(not lamp.lit, "switch/off reaches it too")
	_eq(lamp.calls, 2, "switch/one call per throw")
	_ok(ceiling.visible, "switch/a GROUP gang leaves the ceiling lights alone")

	# What a save does with it: keyed by path, restored through set_lights_on.
	var store := ScenePersistence.new(SLOT_ROOM)
	var saved := store._collect_switches(holder)
	_eq(saved.size(), 1, "switch/a save records the gang")
	sw.set_lights_on(true)
	store._restore_switches(holder, saved)
	_ok(not lamp.lit and not sw.lights_on, "switch/a load puts the lamps back as saved")

	var empty := LightSwitch.new()
	empty.target = LightSwitch.Target.GROUP
	holder.add_child(empty)
	empty.set_lights_on(false)
	_ok(not empty.lights_on, "switch/a gang with no group set does nothing")

	holder.free()


# ── scene tab/ ────────────────────────────────────────────────────────────────

func _group_scene_tab() -> void:
	_eq(RoomCatalog.register_mod_room(SLOT_ROOM, {"path": SCENE, "menu_title": "The Attic"}, OWNER),
		"", "tab/a slot room registers")

	var view := SpawnMenuSceneView.create()
	add_child(view)
	var attic := _card(view, "The Attic")
	_ok(attic != null, "tab/a mod room registered before the tab was built has a card")

	# Mods.apply_live registers rooms after the view exists; opening the tab again
	# has to pick them up.
	_eq(RoomCatalog.register_mod_room(PLAIN_ROOM,
		{"path": SCENE, "menu_title": "The Hall", "has_slots": false}, OWNER), "",
		"tab/a slot-less room registers")
	_ok(_card(view, "The Hall") == null, "tab/no card before the tab is opened again")
	view.show_rooms()
	var hall := _card(view, "The Hall")
	_ok(hall != null, "tab/a room registered later gets a card when the tab opens")
	view.show_rooms()
	_eq(_cards_titled(view, "The Hall"), 1, "tab/opening the tab twice adds no second card")

	if attic != null:
		attic.pressed.emit()
		_eq(view._slot_room, SLOT_ROOM, "tab/a slot room's card opens its own slot grid")
		_ok(view._states_panel.visible, "tab/and shows it")
		view.show_rooms()

	var asked: Array[String] = []
	view.scene_change_requested.connect(func(id: String) -> void: asked.append(id))
	if hall != null:
		hall.pressed.emit()
	_eq(asked, [PLAIN_ROOM] as Array[String], "tab/a slot-less room's card switches straight to it")

	RoomCatalog.drop_mod(OWNER)
	view.show_rooms()
	_ok(_card(view, "The Attic") == null and _card(view, "The Hall") == null,
		"tab/a mod that has gone takes its cards with it")
	_ok(_card(view, RoomCatalog.menu_title_of("arcade")) != null,
		"tab/the shipped cards stay")
	view.free()


func _card(view: SpawnMenuSceneView, title: String) -> Button:
	for child: Node in view._rooms_grid.get_children():
		if child is Button and not child.is_queued_for_deletion() and _title_of(child) == title:
			return child as Button
	return null


func _cards_titled(view: SpawnMenuSceneView, title: String) -> int:
	var n := 0
	for child: Node in view._rooms_grid.get_children():
		if child is Button and _title_of(child) == title:
			n += 1
	return n


func _title_of(card: Node) -> String:
	for label: Node in card.find_children("*", "Label", true, false):
		return (label as Label).text
	return ""


# ── assertions ────────────────────────────────────────────────────────────────

