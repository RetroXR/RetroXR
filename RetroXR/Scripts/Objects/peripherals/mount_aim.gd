## MountAim — what a gun on a pivot (Silent Scope's rifle, Operation Wolf's Uzi) tells the game about where it points: its TRAVEL, spread over the whole picture.
##
## A real one "learns where it points from the analog hard mount beneath it" (arcade.md): the pivot's two potentiometers, not a ray at the glass. Meeting the glass with a ray from the barrel (what a
## free pistol does, and a desktop camera's ray does) cannot work for a rifle on a post at the deck's edge: the glass is almost above the pivot (59 degrees up from it at its middle, 17 cm back) and the
## rifle turns 28 degrees up at most, so in a headset the ray met the glass only at its very bottom and the in-game reticle sat low whatever the hand did (Silent Scope 2, 2026-10-29). The travel is the
## range: the left end of the yaw is the picture's left edge, the top of the pitch its top. Pure, for the tests.
class_name MountAim
extends RefCounted


## The aim in libretro's light-gun coordinates (-0x7fff..0x7fff, y DOWN) for a gun turned `yaw` (radians, positive toward the LEFT, as LightGun's `_mount_yaw` is) and `pitch` (positive UP) within
## `yaw_limit` either way and `pitch_limits` (x down, y up). Held inside the picture at both ends.
static func picture(yaw: float, pitch: float, yaw_limit: float, pitch_limits: Vector2) -> Vector2i:
	var x := clampf(-yaw / yaw_limit, -1.0, 1.0)
	var half := (pitch_limits.y - pitch_limits.x) * 0.5
	var middle := (pitch_limits.y + pitch_limits.x) * 0.5
	var y := clampf(-(pitch - middle) / half, -1.0, 1.0)
	return Vector2i(int(x * 32767.0), int(y * 32767.0))
