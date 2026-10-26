## RopeTuning — live sliders for a cord's VerletRope, on the menu its plug opens.
##
## A debug tool for finding a cord's defaults by eye: switch it on under
## Options > Debug, point at a cable's plug, press Tab, and the plug's menu grows
## a section of sliders that write straight into the rope it hangs from. "Copy"
## puts the values on the clipboard as the lines the cable's .tscn takes, so what
## looked right can be pasted into the scene.
##
## Only the solver's per-step numbers are offered. Every one of them is a plain
## field the sim reads on its next step, so a change shows at once; the layout
## ones (segment_count, segment_length) are read when the rope is built and would
## do nothing until the cable was spawned again.
##
## Not persisted, like everything else on the Debug page: a tuning switch that
## came back after a restart would grow a section on every cable's menu.
class_name RopeTuning
extends RefCounted

## [property, caption, min, max, step]. In the order the .tscn files list them.
const PROPS := [
	["constraint_iterations", "Constraint iterations", 1, 20, 1],
	["stretch_stiffness", "Stretch stiffness", 0.0, 1.0, 0.01],
	["bend_stiffness", "Bend stiffness", 0.0, 1.0, 0.01],
	["damping", "Damping", 0.0, 0.2, 0.001],
	["end_align_stiffness", "End align stiffness", 0.0, 1.0, 0.01],
	["end_stiffness", "End stiffness", 0.0, 1.0, 0.01],
	["end_stiff_segments", "End stiff segments", 0, 8, 1],
]

## The values the rope had when it was first tuned, kept on the rope itself so
## Reset finds them whichever plug's menu it is pressed on.
const AUTHORED_META := &"_rope_tuning_authored"

static var enabled := false


## The rope `obj` hangs from: the first VerletRope that is a direct child of `obj`
## or of one of its ancestors. A plug is a child of its cable's root, and so is
## the rope, which makes this the cable's rope for every lead built that way.
static func rope_of(obj: Node) -> VerletRope:
	var node := obj
	while node != null:
		for child: Node in node.get_children():
			if child is VerletRope:
				return child as VerletRope
		node = node.get_parent()
	return null


## Fill `box` with a slider per property of `rope`, plus Copy and Reset.
static func build(box: VBoxContainer, rope: VerletRope) -> void:
	if not rope.has_meta(AUTHORED_META):
		var authored := {}
		for p: Array in PROPS:
			authored[p[0]] = rope.get(p[0])
		rope.set_meta(AUTHORED_META, authored)

	box.add_child(MenuStyle.label("ROPE TUNING (DEBUG)", 15, MenuStyle.COLOR_TITLE))
	var sliders := {}
	for p: Array in PROPS:
		var prop: String = p[0]
		var row := MenuStyle.slider_row(box, p[1], p[2], p[3], p[4], 60, 14, 28)
		var slider := row[0] as HSlider
		var val := row[1] as Label
		slider.value = rope.get(prop)
		val.text = _shown(slider.value, p[4])
		slider.value_changed.connect(func(v: float) -> void:
			if not is_instance_valid(rope):
				return
			if p[4] is int:
				rope.set(prop, int(v))
			else:
				rope.set(prop, v)
			val.text = _shown(v, p[4]))
		sliders[prop] = slider

	var buttons := MenuStyle.hbox(8)
	box.add_child(buttons)
	var copy := MenuStyle.row_button("Copy", 15, 0, 36, false)
	copy.pressed.connect(func() -> void:
		if is_instance_valid(rope):
			var text := scene_lines(rope)
			DisplayServer.clipboard_set(text)
			print("[rope_tuning] %s\n%s" % [rope.get_parent().name, text]))
	buttons.add_child(copy)
	var reset := MenuStyle.row_button("Reset", 15, 0, 36, false)
	reset.pressed.connect(func() -> void:
		if not is_instance_valid(rope):
			return
		var authored: Dictionary = rope.get_meta(AUTHORED_META)
		for prop: String in sliders:
			# Through the slider, so its label and the rope move together.
			(sliders[prop] as HSlider).value = authored[prop])
	buttons.add_child(reset)


## The tuned values as .tscn property lines, ready to paste under the cable's
## [node name="VerletRope"] header.
static func scene_lines(rope: VerletRope) -> String:
	var lines := PackedStringArray()
	for p: Array in PROPS:
		var v: Variant = rope.get(p[0])
		lines.append("%s = %s" % [p[0], str(v) if p[4] is int else _shown(v, p[4])])
	return "\n".join(lines)


## A value at the precision its slider steps by, so 0.30 does not read 0.3000001.
static func _shown(v: float, step: Variant) -> String:
	if step is int:
		return str(int(v))
	var places := maxi(0, -floori(log(float(step)) / log(10.0) + 0.0001))
	return String.num(v, places)
