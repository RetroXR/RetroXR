## The RXR-004's base: the part of an aerial a player actually picks up.
##
## A pickable and two forwards. Everything the aerial DOES belongs to the Antenna
## root above it; this exists because a lead has no body to grab and the aerial
## does — the same split RfSwitchBody makes, for the same reason.
class_name AntennaBody
extends XRToolsPickable

## Over the rods, not over the base: they stand 0.39 m above the origin.
const HINT_HEIGHT := 0.45

var _hint: HeldHint = null


func _ready() -> void:
	super._ready()
	_hint = HeldHint.attach(self, true, HINT_HEIGHT)
	grabbed.connect(_on_grabbed_signal)
	dropped.connect(_on_dropped_signal)


func _on_grabbed_signal(_pickable: Node3D, by: Node3D) -> void:
	if _hint:
		_hint.on_grabbed(by)


func _on_dropped_signal(_pickable: Node3D) -> void:
	if _hint:
		_hint.on_dropped()


## The options walk stops at the first pickable it meets going up from the pointer's
## hit, and that is this body — so without the forward an aerial would open the
## generic lock-only menu and its tuner settings would be unreachable.
func toggle_options_ui(camera: Node3D) -> void:
	var root := get_parent()
	if is_instance_valid(root) and root.has_method("toggle_options_ui"):
		root.call("toggle_options_ui", camera)


## Bin the whole aerial, not just the base — see RfSwitchBody.drop_and_free.
func drop_and_free() -> void:
	var root := get_parent()
	if is_instance_valid(root) and root.has_method("drop_and_free"):
		root.call("drop_and_free")
	else:
		Vanish.free_node(self)
