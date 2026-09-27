## VirtualRowList — a scrolling list whose cost is O(visible rows), not O(rows).
##
## The existing ROM list builds one HBoxContainer per ROM (spawn_menu.gd
## _populate_cartridges_detail). That is fine for 30 NES files and fatal for a
## server library of 10k+. This keeps a small pool of row Controls, repositions
## them as the view scrolls, and re-binds their contents — so 100,000 rows cost
## the same as 20.
##
## Place it as the direct child of a ScrollContainer:
##
##   var list := VirtualRowList.new()
##   list.row_height = 100
##   list.set_row_builder(func() -> Control: return _make_blank_row())
##   list.set_row_binder(func(row: Control, i: int) -> void: _fill_row(row, i))
##   scroll.add_child(list)
##   list.set_row_count(catalog.count())
class_name VirtualRowList
extends Control

## The window of bound rows moved: different rows are on screen than before.
## For dropping work queued on behalf of rows that have scrolled away.
signal window_moved


## Uniform height of every row, in pixels.
@export var row_height: int = 100:
	set(value):
		row_height = maxi(1, value)
		_update_extent()
		_relayout(true)

## Extra rows kept above and below the viewport so a fast scroll doesn't show
## blanks before the next re-bind lands.
@export var overscan: int = 3

var _count: int = 0
var _builder: Callable = Callable()
var _binder: Callable = Callable()

var _scroll: ScrollContainer = null
var _pool: Array[Control] = []
## Row index currently bound to _pool[0]; -1 forces a full re-bind.
var _first_bound: int = -1


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = false
	_attach_scroll()
	resized.connect(func() -> void: _relayout(true))
	_relayout(true)


## Walk up for the nearest ScrollContainer — the list is usually nested inside a
## VBox that also holds a search box, not parented directly to the scroll.
func _attach_scroll() -> void:
	var node: Node = get_parent()
	while node != null:
		if node is ScrollContainer:
			_scroll = node
			break
		node = node.get_parent()
	if _scroll == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	if bar != null and not bar.value_changed.is_connected(_on_scroll):
		bar.value_changed.connect(_on_scroll)


## The ScrollContainer's content root — its first non-scrollbar child.
func _content_root() -> Control:
	if _scroll == null:
		return null
	for c: Node in _scroll.get_children():
		if c is ScrollBar:
			continue
		if c is Control:
			return c
	return null


## Y position of this list within the scrolled content, so anything stacked
## above it (a search box, a header) doesn't offset every row by its height.
##
## Measured against the content root rather than the ScrollContainer, because
## both move together when scrolling — making this value scroll-INDEPENDENT.
## Deriving it from the viewport instead was subtly wrong: value_changed fires
## before the container re-lays-out its child, so global_position was still the
## pre-scroll one and the computed offset cancelled the scroll out entirely,
## leaving the list convinced it was still at row 0.
func _content_offset() -> float:
	var root := _content_root()
	if root == null:
		return 0.0
	return global_position.y - root.global_position.y


# ── Public API ────────────────────────────────────────────────────────────────

## func() -> Control — allocates one blank row. Called at most pool-size times.
func set_row_builder(cb: Callable) -> void:
	_builder = cb
	_discard_pool()
	_relayout(true)


## func(row: Control, index: int) -> void — fills an existing row for `index`.
## Must handle being called repeatedly on the same Control with different
## indices; disconnect/reconnect any signals it wires up.
func set_row_binder(cb: Callable) -> void:
	_binder = cb
	_relayout(true)


func set_row_count(n: int) -> void:
	_count = maxi(0, n)
	_first_bound = -1
	_update_extent()
	_relayout(true)


func get_row_count() -> int:
	return _count


## Re-run the binder for every visible row, keeping scroll position — for when
## the underlying data changed (a download finished, the cache was evicted).
func rebind_visible() -> void:
	_relayout(true)


## Re-bind one row, if it is on screen. Binding is not cheap, so anything that
## changes a single row (download progress) must not rebind the whole window.
func rebind_index(index: int) -> void:
	if _first_bound < 0 or _binder.is_null():
		return
	var slot := index - _first_bound
	if slot < 0 or slot >= _pool.size():
		return
	if not _pool[slot].visible:
		return
	_binder.call(_pool[slot], index)


## Bring a row to the top of the viewport (used by the A–Z jump strip).
func scroll_to_index(index: int) -> void:
	if _scroll == null:
		return
	var target := clampi(index, 0, maxi(0, _count - 1)) * row_height
	_scroll.scroll_vertical = int(_content_offset()) + target


## Row index at the top of the viewport.
func first_visible_index() -> int:
	if _scroll == null:
		return 0
	var local := float(_scroll.scroll_vertical) - _content_offset()
	return maxi(0, int(floor(local / float(row_height))))


## Row indices currently on screen — used to cancel art fetches that scrolled
## away, so a fast scroll doesn't queue hundreds of covers nobody is looking at.
func visible_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	if _first_bound < 0:
		return out
	for i in _pool.size():
		var idx := _first_bound + i
		if idx < _count and _pool[i].visible:
			out.append(idx)
	return out


# ── Layout ────────────────────────────────────────────────────────────────────

func _update_extent() -> void:
	# Giving the ScrollContainer the full virtual height is what makes the
	# scrollbar behave as if every row existed.
	custom_minimum_size.y = _count * row_height


func _on_scroll(_value: float) -> void:
	_relayout(false)


## `force` re-binds even when the window didn't move (data changed, resize).
func _relayout(force: bool) -> void:
	if not is_inside_tree() or _builder.is_null() or _binder.is_null():
		return
	if _scroll == null:
		_attach_scroll()
		if _scroll == null:
			return

	if _count <= 0:
		_hide_all()
		_first_bound = -1
		return

	var view_h := _scroll.size.y
	var visible_rows := int(ceil(view_h / float(row_height))) + overscan * 2
	visible_rows = mini(visible_rows, _count)

	var first := first_visible_index() - overscan
	first = clampi(first, 0, maxi(0, _count - visible_rows))

	if not force and first == _first_bound and _pool.size() >= visible_rows:
		return

	_ensure_pool(visible_rows)

	var width := size.x
	for i in _pool.size():
		var row := _pool[i]
		var index := first + i
		if index >= _count:
			row.visible = false
			continue
		row.visible = true
		row.position = Vector2(0, index * row_height)
		row.size = Vector2(width, row_height)
		_binder.call(row, index)

	var moved := first != _first_bound
	_first_bound = first
	if moved:
		window_moved.emit()


func _ensure_pool(needed: int) -> void:
	while _pool.size() < needed:
		var row: Control = _builder.call()
		if row == null:
			return
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(row)
		_pool.append(row)


func _discard_pool() -> void:
	for row: Control in _pool:
		if is_instance_valid(row):
			row.queue_free()
	_pool.clear()
	_first_bound = -1


func _hide_all() -> void:
	for row: Control in _pool:
		if is_instance_valid(row):
			row.visible = false
