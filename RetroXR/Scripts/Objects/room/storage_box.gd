## StorageBox — a pickable open-top cardboard box that deletes objects put in it.
## When a held XRToolsPickable enters the TrashArea, its PickableHighlight turns red.
## Releasing the object while it is inside the area deletes it: the object shrinks
## away through Vanish.free_node() rather than blinking out on the release frame.
## The detection loop is this box's; held tests, the outline and the delete are
## Trash's, shared with the MenuTrashBin at the spawn menu's corner.
class_name StorageBox
extends XRToolsPickable

@onready var _trash_area: Area3D = $TrashArea

# Pickables currently tracked as "in trash" (held and inside the detection zone).
# key: XRToolsPickable node, value: true (used as a set)
var _objects_in_trash: Dictionary = {}

# Pickables the zone has reported inside it and not yet reported out, so the
# poll below only runs while there is something to poll. The zone's signals and
# get_overlapping_bodies() are fed from the same overlap map, so a body one can
# see the other can too; the grace frames cover the step between them.
var _zone_bodies: Dictionary = {}
var _poll_frames: int = 0
const POLL_GRACE_FRAMES := 4
var _in_area: Dictionary = {}


func _ready() -> void:
	super._ready()
	_trash_area.body_entered.connect(_on_zone_body_entered)
	_trash_area.body_exited.connect(_on_zone_body_exited)


func _on_zone_body_entered(body: Node3D) -> void:
	if body != self and body is XRToolsPickable:
		_zone_bodies[body] = true
	_poll_frames = POLL_GRACE_FRAMES


func _on_zone_body_exited(body: Node3D) -> void:
	_zone_bodies.erase(body)
	_poll_frames = POLL_GRACE_FRAMES


func _process(_delta: float) -> void:
	if _zone_bodies.is_empty() and _objects_in_trash.is_empty() and _poll_frames <= 0:
		return
	if _poll_frames > 0:
		_poll_frames -= 1

	# Build the current set of all pickables (held or not) overlapping the zone.
	var in_area := _in_area
	in_area.clear()
	for body in _trash_area.get_overlapping_bodies():
		if body == self:
			continue
		var pickable := body as XRToolsPickable
		if pickable:
			in_area[pickable] = true
	for body in _zone_bodies.keys():
		if not is_instance_valid(body):
			_zone_bodies.erase(body)

	# Track newly entered held pickables → turn red.
	for body in in_area.keys():
		var pickable := body as XRToolsPickable
		if Trash.is_held(pickable) and not _objects_in_trash.has(pickable):
			_objects_in_trash[pickable] = true
			Trash.set_highlight(pickable, true)
			print("[StorageBox] '%s' entered trash zone" % pickable.name)

	# Handle existing tracked pickables. keys() is already a copy, so erasing
	# while walking it is safe.
	if _objects_in_trash.is_empty():
		return
	for body in _objects_in_trash.keys():
		if not is_instance_valid(body):
			_objects_in_trash.erase(body)
			continue
		var pickable := body as XRToolsPickable
		if not in_area.has(body):
			# Left the detection zone — restore normal highlight.
			_objects_in_trash.erase(body)
			Trash.set_highlight(pickable, false)
			print("[StorageBox] '%s' left trash zone" % pickable.name)
		elif not Trash.is_held(pickable):
			# Released inside the zone → delete it (with its dependents).
			_objects_in_trash.erase(body)
			Trash.set_highlight(pickable, false)
			print("[StorageBox] deleting '%s'" % pickable.name)
			_delete_with_dependents(pickable)


## Kept for Tests/scene_tests.gd, which bins through the box it built.
func _delete_with_dependents(pickable: XRToolsPickable) -> void:
	Trash.delete_with_dependents(pickable)
