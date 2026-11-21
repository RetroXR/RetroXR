## TouchFeel — how a machine's touch screen meets a fingertip: how close to the
## glass a touch begins, how far off it a touch lifts, and the haptic it gives.
##
## One set per machine (RetroSystem.touch_mm / lift_mm / touch_haptic), set on its
## System tab (TouchMenuRows), saved with the room, and read by every screen that
## machine touches through: the DS and 3DS handhelds' bottom screens
## (DualScreenHandheldModel), a DS/3DS bottom screen shown on a TV and the Wii U
## GamePad's glass (TVTouchSurface). Unset (-1), each screen keeps the distances it
## always had, which are not the same on every screen: touch_screen_defaults_mm().
##
## Distances are from the GLASS, in millimetres, to the fingertip's tip point.
## Lift-off is never closer than touch: the gap between them is what keeps a finger
## resting at the edge of the window from chattering on and off.
class_name TouchFeel
extends RefCounted

const TOUCH_MIN_MM := 1.0
const TOUCH_MAX_MM := 30.0
const LIFT_MAX_MM := 50.0
## Light: a tap you notice, not a buzz. Scaled again by the player's haptics setting
## (the rumble manager), as every pulse is.
const HAPTIC_DEFAULT := 0.2
## One frame of rumble, as Haptics.click: the manager drives 0.1 s per live frame.
const HAPTIC_MS := 10
const HAPTIC_KEY := &"touch_screen"


## The distances `sys`'s screen uses when nothing is set, in mm (touch, lift-off);
## Vector2.ZERO for a machine with no touch screen. A model that has one says so:
## a dual-screen handheld (touch_screen_defaults_mm), or a console whose GamePad is
## the screen (gamepad_rect, the Wii U).
static func defaults_mm(sys: Node) -> Vector2:
	if sys == null or not is_instance_valid(sys) or not sys.has_method("get_model"):
		return Vector2.ZERO
	var model: Object = sys.call("get_model")
	if model == null:
		return Vector2.ZERO
	if model.has_method("touch_screen_defaults_mm"):
		return model.call("touch_screen_defaults_mm")
	if model.has_method("gamepad_rect"):
		return TVTouchSurface.defaults_mm()
	return Vector2.ZERO


static func has_touch_screen(sys: Node) -> bool:
	return defaults_mm(sys) != Vector2.ZERO


## The touch and lift-off distances in METRES for a screen whose own defaults are
## `own_mm`: the machine's, where it has set them, else the screen's own.
static func distances_m(host: Object, own_mm: Vector2) -> Vector2:
	var t := own_mm.x
	var l := own_mm.y
	if host != null and is_instance_valid(host):
		var set_t := float(host.get("touch_mm")) if host.get("touch_mm") != null else -1.0
		var set_l := float(host.get("lift_mm")) if host.get("lift_mm") != null else -1.0
		if set_t >= 0.0:
			t = set_t
		if set_l >= 0.0:
			l = set_l
	l = maxf(l, t)
	return Vector2(t, l) * 0.001


## The machine's touch haptic, 0 (off) to 1.
static func haptic(host: Object) -> float:
	if host == null or not is_instance_valid(host) or host.get("touch_haptic") == null:
		return HAPTIC_DEFAULT
	return clampf(float(host.get("touch_haptic")), 0.0, 1.0)


## The light pulse for a fingertip coming onto the glass, on the hand that did it.
static func pulse(ctrl: XRController3D, host: Object) -> void:
	var m := haptic(host)
	if m > 0.0:
		Haptics.pulse(ctrl, m, HAPTIC_MS, HAPTIC_KEY)


## Keep lift-off at or past touch, by moving the one the player did NOT just move:
## raising touch past lift-off carries lift-off up with it, and lowering lift-off
## under touch carries touch down. Returns (touch, lift-off) in mm.
static func ordered(touch: float, lift: float, moved_touch: bool) -> Vector2:
	touch = clampf(touch, TOUCH_MIN_MM, TOUCH_MAX_MM)
	lift = clampf(lift, TOUCH_MIN_MM, LIFT_MAX_MM)
	if lift < touch:
		if moved_touch:
			lift = touch
		else:
			touch = lift
	return Vector2(touch, lift)


## Set `sys`'s feel from the System tab (mm, mm, 0-1). Logged, so a feel a player
## reports can be read off their log.
static func apply(sys: Node, touch: float, lift: float, haptic_amount: float, moved_touch: bool) -> Vector2:
	var pair := ordered(touch, lift, moved_touch)
	sys.set("touch_mm", pair.x)
	sys.set("lift_mm", pair.y)
	sys.set("touch_haptic", clampf(haptic_amount, 0.0, 1.0))
	print("[Touch] %s: touch within %.1f mm, lifts past %.1f mm, haptic %d%%" % [
		sys.name, pair.x, pair.y, roundi(clampf(haptic_amount, 0.0, 1.0) * 100.0)])
	return pair


## Back to the screen's own distances and the default haptic.
static func reset(sys: Node) -> void:
	sys.set("touch_mm", -1.0)
	sys.set("lift_mm", -1.0)
	sys.set("touch_haptic", HAPTIC_DEFAULT)
	print("[Touch] %s: touch feel back to the screen's own" % sys.name)
