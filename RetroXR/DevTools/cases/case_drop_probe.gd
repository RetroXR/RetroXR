extends Node3D
## Cases dropped on a floor: where they come to rest against it, with and without their contents, as built and as one
## box. Headless is fine (physics only):
##   godot --headless --path RetroXR res://DevTools/cases/case_drop_probe.tscn
## Prints [probe] lines; quits when done.

const CASE_SCENE := preload("res://Scenes/Objects/media/game_case.tscn")
const ROM := "CTR - Crash Team Racing (USA).chd"

var _table: Node3D
var _table_top := 0.0


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 0.02, 8.0)
	fcs.shape = box
	floor_body.add_child(fcs)
	add_child(floor_body)
	floor_body.position = Vector3(0, -0.01, 0)       # top at y = 0
	_table = (load("res://Scenes/Objects/furniture/table.tscn") as PackedScene).instantiate() as Node3D
	add_child(_table)
	_table.position = Vector3(-1.5, 0.0, 1.0)
	for _i in 60:
		await get_tree().physics_frame
	_table_top = _top(_table)
	print("[probe] table top settles at %.4f" % _table_top)
	var rom := RomLibrary.rom_dir_for_system("psx").path_join(ROM)
	# [label, family, variant, contents, one box]
	var drops := [["jewel full", "jewel", "single", true, false], ["jewel empty", "jewel", "single", false, false],
		["wiiu full", "keep", "wiiu", true, false],
		["wiiu empty", "keep", "wiiu", false, false], ["ps2 full", "keep", "ps2", true, false], ["fatbox4 full", "jewel", "fatbox4", true, false],
		["longbox full", "jewel", "longbox", true, false], ["umd full", "keep", "umd", true, false],
		["jewel open", "jewel", "single", true, true], ["wiiu open", "keep", "wiiu", true, true],
		["jewel on table", "jewel", "single", true, false], ["wiiu on table", "keep", "wiiu", true, false]]
	var cases: Array = []
	var x := 0.0
	for d in drops:
		var c := CASE_SCENE.instantiate() as RetroGameCase
		c.systemid = "psx"
		c.rom_path = rom
		c.case_family = str(d[1])
		c.case_variant = str(d[2])
		add_child(c)
		c.add_to_group("spawned")
		c.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x, 0.3, 0))
		x += 0.4
		if d[3]:
			c.spawn_contents(PackedStringArray([rom]))
		if d[4]:
			c.sim.set_angle_deg(c.sim.top(), 180.0)
			c._apply_angles()
		if str(d[0]).ends_with("table"):
			c.global_position = Vector3(_table.global_position.x + (0.0 if d[1] == "jewel" else 0.25), 1.2, _table.global_position.z)
		cases.append([c, str(d[0])])
	for f in 300:
		await get_tree().physics_frame
		if f % 30 == 29:
			var line := ""
			for e in cases:
				line += "%s %+.1f  " % [e[1], _low(e[0]) * 1000.0]
			print("[probe] f%d %s" % [f + 1, line])
	for e in cases:
		var c: RetroGameCase = e[0]
		var surface := _table_top if e[1].ends_with("table") else 0.0
		if e[1].ends_with("open"):
			print("[probe] %s front points %s" % [e[1], c.global_basis.z.snapped(Vector3.ONE * 0.001)])
		var bk := c.manual()
		if bk != null:
			var span: Vector2 = bk._drawn_z_span()
			var to_case := c.global_transform.affine_inverse() * bk.global_transform
			var zs := [(to_case * Vector3(0.03, 0.0, span.x)).z, (to_case * Vector3(0.03, 0.0, span.y)).z]
			var cb := c._closed_box
			print("[probe] %s manual z %.1f..%.1f mm, case %.1f..%.1f mm: %s" % [e[1], minf(zs[0], zs[1]) * 1000.0,
				maxf(zs[0], zs[1]) * 1000.0, cb.position.z * 1000.0, cb.end.z * 1000.0,
				"inside" if minf(zs[0], zs[1]) >= cb.position.z - 0.0001 and maxf(zs[0], zs[1]) <= cb.end.z + 0.0001 else "POKES OUT"])
		print("[probe] %s rests %+.1f mm (lowest corner against the floor's top), lid %.1f, sleeping %s" % [e[1],
			(_low(c) - surface) * 1000.0, c.lid_deg(), c.sleeping])
	get_tree().quit(0)


func _low(c: RetroGameCase) -> float:
	var low := INF
	for s in c.get_children():
		if s is CollisionShape3D and not (s as CollisionShape3D).disabled:
			var sh := s as CollisionShape3D
			for pt in (sh.shape as ConvexPolygonShape3D).points:
				low = minf(low, (sh.global_transform * pt).y)
	return low


## The highest point of a body's solid collision (not its pointer target).
func _top(n: Node) -> float:
	var top := -INF
	for s in n.find_children("*", "CollisionShape3D", true, false):
		var sh := s as CollisionShape3D
		var owner_body := sh.get_parent() as CollisionObject3D
		if not owner_body is PhysicsBody3D or (owner_body.collision_layer & 1048576) != 0 or sh.shape == null or sh.disabled:
			continue
		var ab: AABB = sh.shape.get_debug_mesh().get_aabb()
		for k in 8:
			top = maxf(top, (sh.global_transform * ab.get_endpoint(k)).y)
	return top
