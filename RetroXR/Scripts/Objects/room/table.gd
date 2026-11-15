## Table — a pickable wooden table that can be carried and set down anywhere.
##
## It was inline scenery in the arcade until it became a spawnable object, and the
## one thing that had to change on the way out is collision: the old node had a
## single box over the top slab, so a hand, a controller ray and anything dropped
## beside it all passed straight through the legs. Every leg carries its own shape
## here, which is what makes it a table you can put something UNDER.
##
## Pose is the whole of its state, so it needs no save/load arm beyond a branch in
## ScenePersistence.
##
## CARRIED, WHAT IS ON ITS TOP STAYS ON IT. The furniture built from contracts held what lay on its top in place while
## it was carried (CarryContents) and this table did not: picked up and swung, the things on it slid off. Its top now
## has the same bin, the top slab's footprint from its surface up TOP_BIN_H, and the hold is polled every tick as
## DrawerFurniture polls its own (a ray grab emits no picked_up).
class_name Table
extends XRToolsPickable

## How high over the top the bin reaches, metres (DrawerFurniture.SURFACE_BIN_H).
const TOP_BIN_H := 0.4

var _carry := CarryContents.new()


func _ready() -> void:
	super()
	var top := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if top == null or not top.shape is BoxShape3D:
		push_warning("[Table] %s: no top box (CollisionShape3D): what is on it is not held while it is carried" % name)
		return
	var size := (top.shape as BoxShape3D).size
	_carry.add_bin(self, self, AABB(top.position + Vector3(-size.x, size.y, -size.z) * 0.5,
		Vector3(size.x, TOP_BIN_H, size.z)), collision_layer)
	# After whatever holds it has moved it this tick (CarryContents measures that).
	process_physics_priority = 100
	print("[Table] %s: its top (%.2f x %.2f m at %.2f m) holds what is on it while it is carried" % [name, size.x,
		size.z, top.position.y + size.y * 0.5])


## What it carries things on when it is picked up (HeldObjectPhysics' riders): its top.
func rider_shapes() -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	var top := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if top != null:
		out.append(top)
	return out


## The things it holds in place while it is carried (a test, a probe).
func carry() -> CarryContents:
	return _carry


func _physics_process(delta: float) -> void:
	_carry.step(self, freeze and collision_layer == picked_up_layer, delta)


func _exit_tree() -> void:
	super()
	_carry.release(self)
