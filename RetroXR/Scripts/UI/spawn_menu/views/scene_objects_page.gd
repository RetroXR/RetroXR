## SceneObjectsPage -- the SCENE tab's Objects page: everything spawned in the
## room, nearest first, with how far away it is and a way to find or delete it.
##
## The cartridge that went under the bed, or the pad that fell through the floor,
## had no way back but walking to it. This is a table of every object the item
## menu's Delete could reach -- the rule is Trash.can_delete, so the room's own
## furniture and a device's captive plug never appear -- and each row's Delete is
## that menu's: two taps, then Vanish.shrink_in_place over
## Trash.delete_with_dependents. Netplay needs nothing of its own, since
## ObjectSync despawns on tree_exiting as it does for the menu.
##
## One row per SPAWNED ROOT, not per pickable: a composite lead is one node in
## "spawned" with a pickable plug at each end, and a cover on a console's slot is
## a pickable under the console. A lead's row deletes the lead (through one of its
## plugs, which is how Trash frees a lead); a console's row deletes the console.
##
## Distances move as the player does, so the page re-reads them REFRESH_HZ times a
## second while it is on screen -- labels only. Rows are rebuilt when the set of
## objects changes, and re-ordered when the order does, never every tick.
class_name SceneObjectsPage
extends VBoxContainer

const REFRESH_HZ := 4.0
const DIST_COL_PX := 170
## The icon buttons are the games list's delete button: 76 px, a 40 pt glyph.
const BTN_W := 76
const ICON_SIZE := 40
const ROW_H := 64
const DELETE_CONFIRM_SECONDS := 3.0

## Probes and tests: the eye distances are measured from. Unset, the player's
## XRCamera3D, found as the spawn menu controller finds it.
var camera_override: Node3D = null

var _scroll: ScrollContainer = null
var _rows_box: VBoxContainer = null
var _empty_hint: Label = null
var _camera: Node3D = null
var _accum := 0.0
## Instance ids of the roots the rows were built for, in row order.
var _ids: Array[int] = []
## instance id -> {root, pick, name, row, dist, delete, confirm}
var _rows: Dictionary = {}


static func create() -> SceneObjectsPage:
	var p := SceneObjectsPage.new()
	p.name = "Objects"
	p._build()
	return p


func active_scroll() -> ScrollContainer:
	return _scroll


func _build() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

	var head := MenuStyle.hbox(12)
	head.custom_minimum_size = Vector2(0, 40)
	add_child(head)
	var name_head := MenuStyle.label("Object", 20, MenuStyle.COLOR_LICENSE)
	name_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_head)
	var dist_head := MenuStyle.label("Distance", 20, MenuStyle.COLOR_LICENSE)
	dist_head.custom_minimum_size = Vector2(DIST_COL_PX, 0)
	dist_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(dist_head)
	# Over the two button columns, so the headings line up with what is below them.
	var btn_head := Control.new()
	btn_head.custom_minimum_size = Vector2(BTN_W * 2 + 12, 0)
	head.add_child(btn_head)

	_scroll = MenuStyle.vscroll()
	add_child(_scroll)
	var inner := MenuStyle.vbox(8)
	_scroll.add_child(inner)
	_rows_box = MenuStyle.vbox(6)
	inner.add_child(_rows_box)
	_empty_hint = MenuStyle.hint("Nothing spawned in this room.")
	_empty_hint.visible = false
	inner.add_child(_empty_hint)

	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			refresh())


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	for id: int in _ids:
		var record: Dictionary = _rows[id]
		if record["confirm"] > 0.0:
			record["confirm"] = maxf(0.0, record["confirm"] - delta)
			if record["confirm"] == 0.0:
				_set_delete_prompt(record, false)
	_accum += delta
	if _accum >= 1.0 / REFRESH_HZ:
		_accum = 0.0
		refresh()


## Re-read the room: rebuild the rows if the objects changed, then the distances
## and the order. Public so a test can step it without waiting on the timer.
func refresh() -> void:
	var found := collect(get_tree())
	var eye := _eye_position()
	var dist := {}
	for root_id: int in found:
		var pick: Node3D = found[root_id]["pick"]
		dist[root_id] = eye.distance_to(pick.global_position)
	var order: Array = found.keys()
	order.sort_custom(func(a: int, b: int) -> bool:
		return dist[a] < dist[b] if dist[a] != dist[b] else a < b)

	var same_set := order.size() == _ids.size()
	if same_set:
		for id: int in order:
			if not _rows.has(id):
				same_set = false
				break
	if not same_set:
		_rebuild(order, found)
	elif order != Array(_ids):
		for i in order.size():
			_rows_box.move_child(_rows[order[i]]["row"], i)
		_ids.assign(order)
	for id: int in _ids:
		var record: Dictionary = _rows[id]
		(record["dist"] as Label).text = "%.2f m" % dist[id]
	_empty_hint.visible = _ids.is_empty()


## Every deletable spawned object under `tree`'s root, keyed by its spawned
## root's instance id: {root, pick, name}. `pick` is the pickable a delete goes
## through and the point distances are measured to.
static func collect(tree: SceneTree) -> Dictionary:
	var out := {}
	for node: Node in tree.get_nodes_in_group("spawned"):
		if not node.is_inside_tree() or Vanish.is_vanishing(node):
			continue
		var root := node as Node3D
		if root == null:
			continue
		var pick: XRToolsPickable = null
		if Trash.can_delete(root):
			pick = root as XRToolsPickable
		else:
			# A lead: the node in "spawned" is not itself a pickable, its plugs are.
			for p: Node in root.find_children("*", "XRToolsPickable", true, false):
				if _belongs_to(p, root) and Trash.can_delete(p) and not Vanish.is_vanishing(p):
					pick = p as XRToolsPickable
					break
		if pick == null:
			continue
		out[root.get_instance_id()] = {"root": root, "pick": pick, "name": name_of(root)}
	return out


## Whether `root` is the nearest "spawned" node above `p`: a plug on a lead that
## is snapped into some other spawned device is still the lead's.
static func _belongs_to(node: Node, root: Node) -> bool:
	var n := node
	while n != null:
		if n == root:
			return true
		if n.is_in_group("spawned"):
			return false
		n = n.get_parent()
	return false


## What the row calls an object: its own name for itself where it has one, else
## what it plays or shows, else its kind.
static func name_of(node: Node) -> String:
	for m: String in ["display_name", "display_name_for_toast"]:
		if node.has_method(m):
			var s := str(node.call(m)).strip_edges()
			if not s.is_empty():
				return s
	var label: Variant = node.get("game_label")
	if label is String and not (label as String).strip_edges().is_empty():
		return (label as String).strip_edges()
	for prop: String in ["pdf_path", "video_path", "rom_path", "file_path"]:
		var path: Variant = node.get(prop)
		if path is String and not (path as String).is_empty():
			return (path as String).get_file().get_basename()
	var script := node.get_script() as Script
	var kind := script.get_global_name() if script != null else &""
	var raw := String(kind) if kind != &"" else String(node.name)
	# "@RigidBody3D@42" is a node nobody named.
	if raw.begins_with("@"):
		raw = node.get_class()
	return raw.to_snake_case().capitalize()


func _eye_position() -> Vector3:
	if is_instance_valid(camera_override):
		return camera_override.global_position
	var cam := _player_camera()
	return cam.global_position if cam != null else Vector3.ZERO


func _player_camera() -> Node3D:
	if is_instance_valid(camera_override):
		return camera_override
	if not is_instance_valid(_camera) or not _camera.is_inside_tree():
		var cams := get_tree().root.find_children("*", "XRCamera3D", true, false)
		_camera = cams[0] as Node3D if not cams.is_empty() else null
	return _camera


func _rebuild(order: Array, found: Dictionary) -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_rows.clear()
	_ids.clear()
	for id: int in order:
		var record: Dictionary = found[id].duplicate()
		record["confirm"] = 0.0
		_make_row(record)
		_rows[id] = record
		_ids.append(id)
		_rows_box.add_child(record["row"])


func _make_row(record: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, ROW_H)
	panel.add_theme_stylebox_override("panel", MenuStyle.rounded(MenuStyle.COLOR_SLOT_NORMAL, 6))
	var row := MenuStyle.hbox(12)
	panel.add_child(row)

	var name_lbl := MenuStyle.label(record["name"], 22, MenuStyle.COLOR_TITLE)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.clip_text = true
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_lbl)

	var dist_lbl := MenuStyle.label("", 22, MenuStyle.COLOR_LICENSE)
	dist_lbl.custom_minimum_size = Vector2(DIST_COL_PX, 0)
	dist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dist_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(dist_lbl)

	var locate := _icon_btn(MenuIcons.LOCATE, MenuIcons.TINT_LOCATE, "Locate")
	locate.name = "Locate"
	locate.pressed.connect(_on_locate.bind(record))
	row.add_child(locate)

	# The games list's delete: gone for good (nothing to fetch back), so the
	# DELETE_FOREVER bin, and the warning glyph while it asks again.
	var del := _icon_btn(MenuIcons.DELETE_FOREVER, MenuIcons.TINT_DELETE, "Delete permanently")
	del.name = "Delete"
	del.pressed.connect(_on_delete.bind(record))
	row.add_child(del)

	record["row"] = panel
	record["dist"] = dist_lbl
	record["delete"] = del


func _icon_btn(glyph: int, tint: Color, tip: String) -> Button:
	var b := Button.new()
	b.text = String.chr(glyph)
	b.custom_minimum_size = Vector2(BTN_W, ROW_H - 8)
	b.add_theme_font_override("font", MenuIcons.symbols())
	b.add_theme_font_size_override("font_size", ICON_SIZE)
	b.add_theme_color_override("font_color", tint)
	b.tooltip_text = tip
	return b


func _on_locate(record: Dictionary) -> void:
	var pick: Node3D = record["pick"]
	if not is_instance_valid(pick):
		return
	var cam := _player_camera()
	if cam == null:
		print("[SceneObjects] no player camera to locate '%s' from" % record["name"])
		return
	LocateArrow.on(cam).locate(pick, record["name"])


func _on_delete(record: Dictionary) -> void:
	var pick: Node3D = record["pick"]
	if not is_instance_valid(pick) or not Trash.can_delete(pick):
		print("[SceneObjects] '%s' can no longer be deleted" % record["name"])
		return
	if record["confirm"] <= 0.0:
		record["confirm"] = DELETE_CONFIRM_SECONDS
		_set_delete_prompt(record, true)
		return
	record["confirm"] = 0.0
	print("[SceneObjects] deleting '%s' at %.2f m" % [record["name"],
		_eye_position().distance_to(pick.global_position)])
	# Nothing was let go of, so nothing drops: as the item menu's Delete.
	Vanish.shrink_in_place(Trash.delete_with_dependents.bind(pick as XRToolsPickable))
	refresh()


func _set_delete_prompt(record: Dictionary, asking: bool) -> void:
	var btn: Button = record["delete"]
	if not is_instance_valid(btn):
		return
	btn.text = String.chr(MenuIcons.ERROR if asking else MenuIcons.DELETE_FOREVER)
	btn.tooltip_text = "Tap again to delete permanently" if asking else "Delete permanently"
