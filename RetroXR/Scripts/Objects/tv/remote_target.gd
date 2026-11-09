## RemoteTarget — what a device answers to be driven by the TV remote (TVRemote).
##
## The remote knows no device by class. Anything it is aimed at that is in GROUP and
## answers the two required methods is a target, the set and the decks included, so a
## mod's object becomes one the same way (docs/modding.md "Remote control"):
##
##   func _init() -> void:
##       RemoteTarget.join(self)
##
##   ## Required. The cells of the floating grid: {id, col, row, span?} and a face,
##   ## `glyph` (a TransportGlyphs key) or `text` (printed as it is). Three columns.
##   func remote_layout() -> Array
##   ## Required. Do what cell `id` does. Go through the same path as the device's own
##   ## button, which is what saves it and carries it to netplay peers.
##   func remote_activate(id: String) -> void
##
##   ## Optional. Whether `id` works right now (greyed and skipped when not). Default true.
##   func remote_cell_enabled(id: String) -> bool
##   ## Optional. The face a STATE key wears now: {glyph|text, tint: Color, lean: -1..1}.
##   ## {} keeps the layout's face. Asked every frame the grid shows, so keep it cheap.
##   func remote_cell_face(id: String) -> Dictionary
##   ## Optional. Every face a state key can wear, so it is sized for the largest.
##   func remote_cell_faces(id: String) -> Array
##   ## Optional. Which of THIS device's cells a handset key printed `cell` stands for
##   ## (the DVD's PREV/NEXT are its chapter keys). Default: `cell` itself.
##   func remote_key_cell(cell: String) -> String
##   ## Optional. Anything that changes when the LAYOUT does (which cells there are);
##   ## the grid is rebuilt on a change. Default: the layout never changes.
##   func remote_layout_key() -> Variant
##
## The handset's physical keys (TVRemote.KEY_CELLS) press the cell with their printed
## id: use the shared ids (power, vol_up, playpause, ok, …) and they work; a cell of a
## device's own id is reached through the grid or the lit keys' walk only.
##
## The device must also be FOUND: a collider on the pointable layer (21, a
## `PointerArea` body) somewhere under it, and a `PickableHighlight` child if it wants
## the maroon outline while aimed at.
class_name RemoteTarget
extends RefCounted

const GROUP := &"remote_target"
## The grid is this many cells wide; a cell past it is left out (logged once).
const GRID_COLS := 3

## State tints a face may use: a set that is ON, a muted set.
const TINT_ON := Color(0.30, 1.0, 0.42)
const TINT_ALERT := Color(1.0, 0.35, 0.35)

## The play/pause key's two faces, for a deck's remote_cell_faces.
const PLAY_FACES := [{"glyph": "play"}, {"glyph": "pause"}]

## "device id|problem" already logged, so a bad layout says so once and not per frame.
static var _warned: Dictionary = {}


## Make `device` something the remote drives. Call from its _init.
static func join(device: Node) -> void:
	device.add_to_group(GROUP)


static func is_target(node: Node) -> bool:
	if not (node is Node3D) or not node.is_in_group(GROUP):
		return false
	if node.has_method("remote_layout") and node.has_method("remote_activate"):
		return true
	_warn_once(node, "joined %s but has no remote_layout/remote_activate: not a target" % GROUP)
	return false


## Walk a collider up its ancestors to the device that owns it, or null.
static func of(node: Node) -> Node3D:
	while node:
		if is_target(node):
			return node as Node3D
		node = node.get_parent()
	return null


## The device's layout, every cell checked: one with no id, no face or that runs off
## the grid is left out and logged once.
static func layout(device: Node) -> Array:
	var raw: Variant = device.call("remote_layout")
	if not (raw is Array):
		_warn_once(device, "remote_layout() returned %s, not an Array" % type_string(typeof(raw)))
		return []
	var cells: Array = []
	for spec: Variant in raw:
		var why := _bad_cell(spec)
		if not why.is_empty():
			_warn_once(device, "cell %s left out: %s" % [str(spec), why])
			continue
		cells.append(spec)
	return cells


static func _bad_cell(spec: Variant) -> String:
	if not (spec is Dictionary):
		return "not a Dictionary"
	var d := spec as Dictionary
	if str(d.get("id", "")).is_empty():
		return "no id"
	if not d.has("glyph") and not d.has("text"):
		return "no glyph or text"
	var col: Variant = d.get("col")
	var row: Variant = d.get("row")
	if not (col is int or col is float) or not (row is int or row is float):
		return "col and row must be numbers"
	var span := float(d.get("span", 1))
	if float(col) < 0.0 or int(row) < 0 or span <= 0.0 or float(col) + span > float(GRID_COLS) + 0.001:
		return "outside the %d-column grid" % GRID_COLS
	return ""


static func cell_enabled(device: Node, id: String) -> bool:
	if device.has_method("remote_cell_enabled"):
		return bool(device.call("remote_cell_enabled", id))
	return true


static func activate(device: Node, id: String) -> void:
	device.call("remote_activate", id)


static func face(device: Node, id: String) -> Dictionary:
	if device.has_method("remote_cell_face"):
		var f: Variant = device.call("remote_cell_face", id)
		if f is Dictionary:
			return f
	return {}


static func faces(device: Node, id: String) -> Array:
	if device.has_method("remote_cell_faces"):
		var f: Variant = device.call("remote_cell_faces", id)
		if f is Array:
			return f
	return []


static func key_cell(device: Node, cell: String) -> String:
	if device.has_method("remote_key_cell"):
		return str(device.call("remote_key_cell", cell))
	return cell


static func layout_key(device: Node) -> Variant:
	if device.has_method("remote_layout_key"):
		return device.call("remote_layout_key")
	return null


## Whether two layout keys differ, without comparing values of different types.
static func layout_changed(a: Variant, b: Variant) -> bool:
	return typeof(a) != typeof(b) or a != b


# ── Helpers for a deck ────────────────────────────────────────────────────────

## A transport is playing: `is_playing`, and not paused when it can say so.
static func playing(device: Node) -> bool:
	if not bool(device.get("is_playing")):
		return false
	if device.has_method("is_paused"):
		return not bool(device.call("is_paused"))
	return true


## One Play/Pause cell: pause what plays, else (re)start it, through the device's own
## remote_pause / remote_play.
static func toggle_play(device: Node) -> void:
	device.call("remote_pause" if playing(device) else "remote_play")


## The play/pause key's face now.
static func play_face(device: Node) -> Dictionary:
	return {"glyph": "pause" if playing(device) else "play"}


static func _warn_once(device: Node, what: String) -> void:
	var key := "%d|%s" % [device.get_instance_id(), what]
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("[RemoteTarget] %s: %s" % [device.name, what])
