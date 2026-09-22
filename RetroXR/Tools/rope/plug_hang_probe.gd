## A loose plug hanging off a table by its cord — does it settle pointing along
## the cord, the way a real one hangs?
##
##   "$godot" --headless --path RetroXR res://Tools/rope/plug_hang_probe.tscn
##   ... -- --no-couple    the cord never pushes the plug (the control leg)
##
## The plug starts turned 90 degrees off the cord. Coupled, the cord's boot turns
## it until its exit axis runs back up the cord; uncoupled nothing does, and it
## hangs off its cord boss at whatever angle gravity leaves it — the measurement
## has to tell those two apart or it proves nothing. A sign error in the coupling
## shows as the angle growing, or the plug spinning (`spin`).
##
## Prints the angle between the plug's exit axis and the cord leaving it, every
## 90 ticks, and the plug's angular speed at the end.
##
## Nothing in the rope holds a plug's weight up (anchor_pull is 0 in every
## scene); in the room the host does, with a hard tether clamp. This probe runs
## the same clamp as RetroSystem._clamp_plug after every physics tick.

extends Node

const PLAIN := preload("res://Scenes/Objects/cables/cable.tscn")
const TABLE_TOP := 0.75


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT"); get_tree().quit(1))
	var no_couple := OS.get_cmdline_user_args().has("--no-couple")
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	for spec: Array in [
		[Vector3(8.0, 0.2, 8.0), Vector3(0.0, -0.1, 0.0)],
		[Vector3(0.6, 0.05, 0.6), Vector3(-0.3, TABLE_TOP - 0.025, 0.0)],
	]:
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[0]
		col.shape = box
		col.position = spec[1]
		body.add_child(col)

	var plain: Node3D = PLAIN.instantiate()
	add_child(plain)
	await get_tree().process_frame
	for n: String in ["CablePlugL", "CablePlugR"]:
		var extra := plain.get_node_or_null(n)
		if extra != null:
			extra.queue_free()
	var mount := Node3D.new()
	mount.position = Vector3(-0.15, TABLE_TOP + 0.01, 0.0)
	mount.rotation_degrees = Vector3(0, -90, 0)  # cord leaves along +X, over the edge
	add_child(mount)
	var plug: RigidBody3D = plain.get_node("CablePlug")
	# Hanging 25 cm below the edge, turned so its exit axis points sideways (+Z)
	# instead of up the cord.
	plug.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.05, TABLE_TOP - 0.25, 0.0))
	var rope: VerletRope = plain.get_node("VerletRope")
	rope.ribbon_count = 1
	rope.fray_segments_end = 0
	rope.start_node = mount
	rope.end_node = plug
	rope.end_anchor_offset = plug.get("cable_anchor")
	rope.set_rope_length(0.45)
	if no_couple:
		rope.end_align_stiffness = 0.0
	rope._init_points()

	var exit_local: Vector3 = rope.end_exit_axis
	var reach := rope.segment_count * rope.segment_length
	for t in range(541):
		await get_tree().physics_frame
		var diff := plug.global_position - mount.global_position
		if diff.length() > reach:
			var dir := diff.normalized()
			plug.global_position = mount.global_position + dir * reach
			var outward := dir.dot(plug.linear_velocity)
			if outward > 0.0:
				plug.linear_velocity -= dir * outward
		if t % 90 == 0:
			var pts: PackedVector3Array = rope.get_points()
			var last := rope.point_count() - 1
			var cord: Vector3 = (pts[last - 3] - pts[last]).normalized()
			var exit: Vector3 = (plug.global_transform.basis * exit_local).normalized()
			print("[probe] t=%3d angle(exit, cord)=%5.1f deg  plug y=%.3f" % [
				t, rad_to_deg(exit.angle_to(cord)), plug.global_position.y])
	print("[probe] %s spin=%.3f rad/s  rope asleep=%s" % [
		"no-couple" if no_couple else "coupled", plug.angular_velocity.length(),
		str(rope.is_sleeping())])
	get_tree().quit(0)
