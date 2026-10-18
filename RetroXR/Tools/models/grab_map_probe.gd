## Maps what a desktop pointer aimed at each point of the arcade cabinet's front would DO:
## grab it, operate a control, or nothing. Prints a grid (rows are heights, columns across).
##   G grab the cabinet   B a button/control   . nothing
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")


func _ready() -> void:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = "arcade_cabinet_generic"
	sys.systemid = "arcade"
	sys.freeze = true
	add_child(sys)
	var hand := Node3D.new()
	hand.set_script(load("res://Scripts/Desktop/desktop_hand_pivot.gd"))
	add_child(hand)
	for i in 10:
		await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	print("[probe] can_pick_up=", sys.can_pick_up(hand), " enabled=", sys.enabled, " locked=", ObjectLock.is_locked(sys))
	var lines: Array[String] = []
	var y := 1.75
	while y > 0.05:
		var row := "%.2f " % y
		var x := -0.32
		while x <= 0.321:
			var t := InteractionResolver.resolve_desktop(space, Vector3(x, y, 1.8), Vector3(x, y, -0.2), hand)
			var c := "."
			if t.is_valid():
				c = "G" if t.can_grab else ("B" if t.can_activate else "?")
			row += c
			x += 0.04
		lines.append(row)
		y -= 0.075
	for l in lines:
		print("[probe] ", l)
	# And from a slant, as a standing player sees it: eye 1.6 m up, 1.6 m away.
	var grab := 0
	var total := 0
	for yy in [0.2, 0.5, 0.9, 1.2, 1.5, 1.7]:
		for xx in [-0.25, 0.0, 0.25]:
			var tt := InteractionResolver.resolve_desktop(space, Vector3(0, 1.6, 1.6), Vector3(xx, yy, 0.4), hand)
			total += 1
			if tt.is_valid() and tt.can_grab:
				grab += 1
	print("[probe] from eye height, %d of %d aimed points are a grab" % [grab, total])
	get_tree().quit(0)
