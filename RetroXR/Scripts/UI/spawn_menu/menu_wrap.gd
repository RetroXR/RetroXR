class_name MenuWrap
extends RefCounted
## Word wrap for every Label a menu builds, so a sentence fits the panel instead
## of running off its right edge.
##
## Most rows are built with MenuStyle.label(), which never wrapped: a Label that
## does not wrap asks for its WHOLE text as its minimum width, and with the
## views' horizontal scroll disabled that minimum climbs to the panel. One long
## description therefore made the whole page wider than the menu, so the text was
## clipped AND every switch and dropdown on the right went off the edge with it.
## 194 call sites build labels that way, so the menu wraps them as they arrive
## rather than each site remembering to.
##
## A label wraps when its container gives it the row's width: a column (VBox,
## Margin, Panel) or a row it EXPANDS in. A label sized to its text in a row (a
## value read-out, a unit) keeps one line. Labels that already chose wrapping,
## clipping or trimming are left alone.

## A wrapped label still asks for this much width (or its text's, if less), so a
## column whose width nothing else sets cannot squeeze it to a word a line.
const MIN_WIDTH := 320.0


## Wraps every Label that enters `root`'s subtree from now on, for as long as
## `root` lives. Call it before the menu's rows are built.
static func watch(root: Control) -> void:
	var tree := root.get_tree()
	if tree == null:
		push_warning("[MenuWrap] %s is not in the tree; nothing wraps" % root.name)
		return
	var on_added := func(node: Node) -> void:
		if node is Label and root.is_ancestor_of(node):
			apply(node as Label)
	tree.node_added.connect(on_added)
	root.tree_exiting.connect(func() -> void:
		if tree.node_added.is_connected(on_added):
			tree.node_added.disconnect(on_added), CONNECT_ONE_SHOT)
	for l: Node in root.find_children("*", "Label", true, false):
		apply(l as Label)


## Turns wrapping on for one label if its place in the layout allows it.
static func apply(l: Label) -> void:
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF or l.clip_text \
			or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
		return
	var parent := l.get_parent()
	var spans := parent is VBoxContainer or parent is MarginContainer \
		or parent is PanelContainer \
		or (parent is HBoxContainer and l.size_flags_horizontal & Control.SIZE_EXPAND)
	if not spans:
		return
	if l.custom_minimum_size.x <= 0.0:
		var font := l.get_theme_font("font")
		var natural := 0.0
		if font != null:
			natural = font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				l.get_theme_font_size("font_size")).x
		l.custom_minimum_size.x = minf(natural, MIN_WIDTH)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
