## Does the player still LOOK AROUND while seated, through the game's real rig? Instantiates
## Scenes/player_rig.tscn, sits it on a chair, injects mouse motion as the desktop's mouse-look
## reads it, and prints the camera's heading before and after. Headless is fine (no picture).
##
##   "$godot" --headless --path RetroXR res://Tools/models/seat_look_probe.tscn [-- --oldbug]
##
## --oldbug switches the body off after sitting, as the first Seat did: the head then cannot turn (turned=false).
extends Node3D


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[probe] TIMED OUT")
		get_tree().quit(2))
	var rig := (load("res://Scenes/player_rig.tscn") as PackedScene).instantiate() as PlayerRig
	add_child(rig)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20, 0.2, 20)
	cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position.y = -0.1
	add_child(floor_body)
	for i in 20:
		await get_tree().physics_frame
	var seat := (load("res://Scenes/Objects/furniture/seat_chair.tscn") as PackedScene).instantiate() as Seat
	seat.freeze = true
	seat.position = Vector3(2.0, 0.0, 2.0)
	add_child(seat)
	await get_tree().physics_frame
	print("[probe] body enabled before: ", rig.body.enabled, " camera y: ", rig.camera.position.y)
	print("[probe] sit: ", seat.sit())
	for i in 10:
		await get_tree().physics_frame
	if "--oldbug" in OS.get_cmdline_user_args():
		rig.body.enabled = false          # what the first version of Seat did: the control leg
	var y0 := Seat.yaw_of(rig.camera.global_transform.basis)
	var p0 := rig.origin.global_position
	print("[probe] seated: body enabled=", rig.body.enabled, " camera y=", rig.camera.position.y, " yaw=", y0)
	for i in 30:
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(40, 0)
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await get_tree().physics_frame
	var y1 := Seat.yaw_of(rig.camera.global_transform.basis)
	print("[probe] after mouse motion: yaw=", y1, " turned=", absf(wrapf(y1 - y0, -PI, PI)) > 0.1,
		" origin moved=", rig.origin.global_position.distance_to(p0))
	seat.stand()
	for i in 10:
		await get_tree().physics_frame
	print("[probe] stood: camera y=", rig.camera.position.y, " head at ", rig.camera.global_position, " seat stand point ", seat.stand_point())
	get_tree().quit(0)
