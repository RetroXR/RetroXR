## passthrough_init.gd — Root script for PassthroughScene.tscn.
##
## Enables OpenXR passthrough so the user sees the real world.
## Requires project setting xr/openxr/extensions/meta/passthrough=true so the
## XR_FB_passthrough extension wrapper is registered and ALPHA_BLEND is available.
## See: https://docs.godotengine.org/en/4.6/tutorials/xr/ar_passthrough.html
extends Node3D

## Locomotion can be suspended for as long as passthrough is on: you are standing
## in your actual room and can see it, so sliding the world past you puts the two
## out of register. Whether it is suspended is the player's call
## (AppPrefs.passthrough_locomotion), because a real room is usually smaller than
## the one being furnished and walking alone cannot reach the far end of it.
const LOCO_OWNER := &"passthrough"

@onready var _viewport: Viewport = get_viewport()
@onready var _environment: Environment = $WorldEnvironment.environment

var _loco: LocomotionManager = null
## Whether passthrough actually came up. The block follows this and the pref
## together, so flipping the switch from the menu can only move the player while
## they are really in passthrough.
var _passthrough_on := false


func _ready() -> void:
	var xr_interface := XRServer.find_interface("OpenXR")
	if not xr_interface or not xr_interface.is_initialized():
		push_warning("PassthroughInit: OpenXR not initialized, running in flat screen mode")
		return

	# XR is already running from the arcade scene (use_xr, roomscale were set there).
	# Defer so the viewport is fully settled after the scene change.
	call_deferred("_enable_passthrough")


func _enable_passthrough() -> void:
	var xr_interface: XRInterface = XRServer.primary_interface
	if not xr_interface:
		push_warning("PassthroughInit: no primary XR interface")
		return

	if not XrPassthrough.enable(_viewport):
		push_warning("PassthroughInit: no passthrough blend mode supported — modes: %s"
			% str(xr_interface.get_supported_environment_blend_modes()))
		return

	# BG_COLOR with fully transparent black so the passthrough layer shows through.
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR

	# Tied to passthrough actually being on, not merely to this scene loading —
	# every path above returns early when it is not available (no OpenXR, no
	# blend mode), and blocking movement in a bare scene would strand the player.
	_passthrough_on = true
	refresh_locomotion()

	print("PassthroughInit: passthrough enabled (blend_mode=%d)" % xr_interface.environment_blend_mode)


func _disable_passthrough() -> void:
	# Released first and unconditionally: the returns below are all reasons the
	# blend mode cannot be restored, none of them a reason to leave the player
	# unable to move.
	_passthrough_on = false
	_block_locomotion(false)

	var xr_interface: XRInterface = XRServer.primary_interface
	if not xr_interface:
		return

	var modes := xr_interface.get_supported_environment_blend_modes()
	if XRInterface.XR_ENV_BLEND_MODE_OPAQUE in modes:
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE

	_viewport.transparent_bg = false


func _exit_tree() -> void:
	_disable_passthrough()


## Re-read the pref and block or release accordingly. Called by the OPTIONS switch,
## which lands on SpawnMenuController while this room is the current scene.
func refresh_locomotion() -> void:
	var prefs := get_node_or_null("/root/AppPrefs")
	var allowed: bool = prefs == null or prefs.passthrough_locomotion
	_block_locomotion(_passthrough_on and not allowed)


## CHANNEL_ALL covers direct movement, snap turn and teleport; CHANNEL_DESKTOP_MOVE
## covers the keyboard providers, which are inert in a headset but cost nothing to
## include and keep this correct if passthrough is ever reachable outside one.
func _block_locomotion(on: bool) -> void:
	if _loco == null or not is_instance_valid(_loco):
		# The manager lives on the player rig, which outlives the room scene, so
		# it is found rather than held.
		if not is_inside_tree():
			return
		_loco = get_tree().root.find_child("LocomotionManager", true, false) as LocomotionManager
	if _loco == null:
		if on:
			push_warning("PassthroughInit: no LocomotionManager — movement stays enabled")
		return
	_loco.set_block(LOCO_OWNER, LocomotionManager.CHANNEL_ALL, on)
	_loco.set_block(LOCO_OWNER, LocomotionManager.CHANNEL_DESKTOP_MOVE, on)
