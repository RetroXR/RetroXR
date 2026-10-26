class_name LocomotionManager
extends Node

const CHANNEL_LEFT := &"left"
const CHANNEL_RIGHT := &"right"
const CHANNEL_ALL := &"all"

## Desktop mode has no hands, so its providers are separate nodes with their own
## names and need their own channel. Covers the keyboard-driven providers only —
## MovementDesktopTurn (mouse-look) is deliberately never gated, because turning
## is how the player drags the virtual mouse.
const CHANNEL_DESKTOP_MOVE := &"desktop_move"

var _move_turn: Node = null
var _func_teleport: Node = null
var _move_direct: Node = null
var _desktop_movers: Array[Node] = []

var _left_blocks := {}
var _right_blocks := {}
var _desktop_blocks := {}


## True when the left stick aims a teleport instead of walking. Mirrors
## AppPrefs.locomotion_teleport; set through set_teleport_mode so the change
## takes effect immediately rather than at the next scene load.
var _teleport_mode := false


func _ready() -> void:
	call_deferred("_deferred_setup")


## Choose which of the two left-stick locomotion verbs is live. Exactly one is
## ever enabled: with both on, pushing the stick forward would walk AND start
## aiming a teleport.
func set_teleport_mode(on: bool) -> void:
	if on == _teleport_mode:
		return
	_teleport_mode = on
	# No need to cancel an aim in progress: FunctionTeleport._physics_process
	# clears is_teleporting and hides the arc and target on its first disabled
	# tick, then stops itself.
	_apply()


func is_teleport_mode() -> bool:
	return _teleport_mode


func _deferred_setup() -> void:
	_move_turn = _require("MovementTurn")
	_func_teleport = _require("FunctionTeleport")
	_move_direct = _require("MovementDirect")
	# These are what desktop mode actually runs. They were missing for a long
	# time, so nothing was ever blocked outside VR — hence the push_warning: a
	# rename must fail loudly instead of silently disabling arbitration again.
	_desktop_movers.clear()
	for provider_name: String in ["MovementDesktopDirect", "MovementDesktopCrouch",
			"MovementDesktopWalk"]:
		var node := _require(provider_name)
		if node != null:
			_desktop_movers.append(node)
	var prefs := get_node_or_null("/root/AppPrefs")
	if prefs != null:
		_teleport_mode = prefs.locomotion_teleport
	_apply()


func _require(provider_name: String) -> Node:
	var node := get_tree().root.find_child(provider_name, true, false)
	if node == null:
		push_warning("[LocomotionManager] no node named '%s' — it will never be blocked"
			% provider_name)
	return node


## Block or release one channel for one owner.
##
## `block_owner` MUST be unique per object whenever more than one object of a
## kind can be holding a block at once. A block is keyed on (channel, owner) and
## `active = false` ERASES that key, so two objects sharing a literal overwrite
## each other -- and because the held peripherals each write BOTH VR channels
## from whichever hand is holding THEM, sharing means the last one to update
## wins and the loser's block is simply gone.
##
## That is not hypothetical: the Wiimote, the TV remote, the light gun and the
## retro controller all passed &"retro_hold" here. Holding a Wiimote and then
## putting down a TV remote erased the Wiimote's block outright, with nothing to
## restore it until the Wiimote itself was re-grabbed -- and all four read their
## own input off that hand's thumbstick, so the player walked while playing.
## They now pass `_vr_block_owner()`, which folds in the instance id.
func set_block(block_owner: StringName, channel: StringName, active: bool) -> void:
	match channel:
		CHANNEL_LEFT:
			_set_channel_block(_left_blocks, block_owner, active)
		CHANNEL_RIGHT:
			_set_channel_block(_right_blocks, block_owner, active)
		CHANNEL_ALL:
			_set_channel_block(_left_blocks, block_owner, active)
			_set_channel_block(_right_blocks, block_owner, active)
		CHANNEL_DESKTOP_MOVE:
			_set_channel_block(_desktop_blocks, block_owner, active)
		_:
			push_warning("[LocomotionManager] unknown channel '%s'" % [channel])
			return

	_apply()


func clear_owner(block_owner: StringName) -> void:
	_left_blocks.erase(block_owner)
	_right_blocks.erase(block_owner)
	_desktop_blocks.erase(block_owner)
	_apply()


func is_blocked(channel: StringName) -> bool:
	match channel:
		CHANNEL_LEFT:
			return not _left_blocks.is_empty()
		CHANNEL_RIGHT:
			return not _right_blocks.is_empty()
		CHANNEL_ALL:
			return not _left_blocks.is_empty() or not _right_blocks.is_empty()
		CHANNEL_DESKTOP_MOVE:
			return not _desktop_blocks.is_empty()
		_:
			return false


func _set_channel_block(blocks: Dictionary, block_owner: StringName, active: bool) -> void:
	if active:
		blocks[block_owner] = true
	else:
		blocks.erase(block_owner)


func _apply() -> void:
	# Walking and teleport are both LEFT-stick verbs and mutually exclusive, so
	# the left channel gates them together and the mode picks which one it lets
	# through. Turning stays on the right stick either way.
	var left_enabled := _left_blocks.is_empty()
	_set_node_enabled(_move_direct, left_enabled and not _teleport_mode)
	_set_node_enabled(_func_teleport, left_enabled and _teleport_mode)
	_set_node_enabled(_move_turn, _right_blocks.is_empty())
	var desktop_enabled := _desktop_blocks.is_empty()
	for mover: Node in _desktop_movers:
		_set_node_enabled(mover, desktop_enabled)


func _set_node_enabled(node: Node, value: bool) -> void:
	if node and "enabled" in node:
		node.set("enabled", value)
