## ConsoleStand — a stand a console is mounted in (a PS2's vertical stand, the
## Wii's cradle), built from its StandCatalog row.
##
## The stand is a pickable of its own carrying one snap zone, the StandMount, at
## the row's seat. A console offered to it is taken by its StandFoot for the
## row's face, so the STAND decides how it stands. From then on the two are one
## body (SeatedCollision lends the console's shapes to the stand): carry the stand
## and the console comes with it; reach for the console and it comes off.
##
## SpeakerStand's arrangement: the STAND records what is on it (its save entry's
## "console"), and RetroSystem knows nothing about stands beyond growing the feet.
## A seated console follows its carrier on every peer (object_sync skips a
## zone-snapped body), so netplay needs nothing here either.
class_name ConsoleStand
extends XRToolsPickable

const SNAP_ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")

## Every stand joins this, so a sweep can find them without testing the class.
const GROUP := "console_stand"

## How far out a console is caught when it is let go: what enters is a whole
## console lowered in, as onto an expansion unit (ExpansionPort's 0.16).
const CAPTURE := 0.15

## Which stand this is (a StandCatalog id). Set before it enters the tree: the
## body is built from it in _ready.
@export var stand_id := ""

var _mount: XRToolsSnapZone = null
## What is seated, kept so its exemptions can be undone after it is gone.
var _console: RetroSystem = null


func _ready() -> void:
	_build()
	super._ready()
	add_to_group("spawned")
	add_to_group(GROUP)


func _build() -> void:
	var r := StandCatalog.row(stand_id)
	if r.is_empty():
		push_warning("[ConsoleStand] no stand '%s' in StandCatalog -- an empty base" % stand_id)
		return
	mass = float(r.get("mass", mass))
	var scene_path := str(r.get("scene", ""))
	var authored := not scene_path.is_empty() and ResourceLoader.exists(scene_path)
	if authored:
		var model := (load(scene_path) as PackedScene).instantiate() as Node3D
		model.name = "Model"
		add_child(model)
	elif not scene_path.is_empty():
		push_warning("[ConsoleStand] %s: model %s is missing -- the primitive stands in"
			% [stand_id, scene_path])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = r.get("color", Color(0.2, 0.2, 0.22))
	mat.roughness = 0.6
	var pointer := get_node_or_null("PointerArea") as CollisionObject3D
	var i := 0
	for part: Dictionary in r.get("parts", []):
		var shape: Shape3D
		var mesh: Mesh
		if part.has("cylinder"):
			var rh: Array = part["cylinder"]
			var cyl := CylinderShape3D.new()
			cyl.radius = float(rh[0])
			cyl.height = float(rh[1])
			shape = cyl
			var cm := CylinderMesh.new()
			cm.top_radius = cyl.radius
			cm.bottom_radius = cyl.radius
			cm.height = cyl.height
			mesh = cm
		else:
			var bs := BoxShape3D.new()
			bs.size = part.get("box", Vector3(0.05, 0.01, 0.05))
			shape = bs
			var bm := BoxMesh.new()
			bm.size = bs.size
			mesh = bm
		var at: Vector3 = part.get("position", Vector3.ZERO)
		var col := CollisionShape3D.new()
		col.name = "Part%d" % i
		col.shape = shape
		col.position = at
		add_child(col)
		# What the desktop ray and the pointer find: the same shapes.
		if pointer != null:
			var hit := CollisionShape3D.new()
			hit.shape = shape
			hit.position = at
			pointer.add_child(hit)
		if not authored:
			var mi := MeshInstance3D.new()
			mi.name = "PartMesh%d" % i
			mi.mesh = mesh
			mi.material_override = mat
			mi.position = at
			add_child(mi)
		i += 1
	var face := StandCatalog.face_of(stand_id)
	var zone := SNAP_ZONE_SCENE.instantiate() as XRToolsSnapZone
	zone.name = "StandMount"
	zone.snap_require = ExpansionPort.GROUP_SYSTEM
	zone.snap_filter = _accepts
	zone.grab_distance = CAPTURE
	zone.add_to_group(StandCatalog.zone_group(face))
	add_child(zone)
	zone.transform = StandCatalog.seat_transform(stand_id)
	zone.has_picked_up.connect(_on_console_in)
	zone.has_dropped.connect(_on_console_out)
	_mount = zone
	print("[ConsoleStand] built %s (%s face, seat %s, %d parts, %s)"
		% [stand_id, face, zone.position, i, "model" if authored else "primitive"])


## Only a console this stand was made for, and only once it has the foot to be
## taken by: without one the zone would seat it where it happened to be.
func _accepts(obj: Node3D) -> bool:
	var sys := obj as RetroSystem
	if sys == null:
		return false
	if not StandCatalog.fits(stand_id, sys.systemid, StandFoot.resolved_model_id(sys)):
		return false
	StandFoot.build_for(sys)
	return StandFoot.find(sys, StandCatalog.face_of(stand_id)) != null


## The stand's mount, so a restore or a suite can reach it.
func mount() -> XRToolsSnapZone:
	return _mount


## The console mounted in this stand, or null.
func seated_console() -> RetroSystem:
	if _mount == null or not is_instance_valid(_mount.picked_up_object):
		return null
	return _mount.picked_up_object as RetroSystem


## The console stands IN the stand -- its box overlaps the cradle by design -- so
## the two are exempt from each other, and its shapes are lent to the stand so
## the pair rests and is pushed as one.
func _on_console_in(what: Node3D) -> void:
	_console = what as RetroSystem
	if _console == null:
		return
	add_collision_exception_with(_console)
	SeatedCollision.lend(self, _console, _mount)
	print("[ConsoleStand] %s took %s (%s) on its %s face"
		% [stand_id, _console.name, _console.systemid, StandCatalog.face_of(stand_id)])


func _on_console_out() -> void:
	SeatedCollision.withdraw_zone(self, _mount)
	if is_instance_valid(_console):
		remove_collision_exception_with(_console)
		print("[ConsoleStand] %s let go of %s" % [stand_id, _console.name])
	_console = null


## Mount `sys` after a save restore, bypassing the reach. The console's feet are
## built from its measured body, which a restore can reach before the model has
## loaded, so this waits a few frames for them rather than seating it footless.
func restore_console(sys: RetroSystem) -> void:
	if _mount == null or sys == null:
		return
	if not StandCatalog.fits(stand_id, sys.systemid, StandFoot.resolved_model_id(sys)):
		push_warning("[ConsoleStand] %s does not fit %s (%s) -- left off"
			% [stand_id, sys.name, sys.systemid])
		return
	for _i in 30:
		if StandFoot.build_for(sys):
			break
		await get_tree().process_frame
		if not is_instance_valid(sys) or not is_instance_valid(_mount):
			return
	if StandFoot.find(sys, StandCatalog.face_of(stand_id)) == null:
		push_warning("[ConsoleStand] %s: %s never measured a body -- left off" % [stand_id, sys.name])
		return
	_mount.pick_up_object(sys)


## Let go of the console and free the stand. Looked for BY NAME by clear_scene
## and StorageBox, as SpeakerStand's is. The console is the player's, so a stand
## put away leaves it in the room.
func drop_and_free() -> void:
	if _mount != null and is_instance_valid(_mount.picked_up_object):
		_mount.drop_object()
	queue_free()
