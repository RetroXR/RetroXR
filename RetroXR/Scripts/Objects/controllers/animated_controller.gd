## AnimatedController — a RetroController whose controls move.
##
## Identical hold/plug/cable/rumble/netplay behaviour to RetroController (it is a
## thin subclass); the only addition is driving separated button/stick meshes from
## the exact per-frame joypad state pushed by _send_joypad(). Buttons depress
## (translate along a per-entry direction), D-pads rock about a pivot and analog
## sticks tilt and click.
##
## Every pad in Scenes/Objects/controllers/ that has moving parts derives from
## this — the imported console models (which find their meshes by name inside the
## .glb) and the pads authored from primitives (which bind theirs by node path).
## Subclasses supply only _cache_meshes(); the animation itself is shared.
class_name AnimatedController
extends RetroController

# Press depths (metres) and tilt limits (degrees). Tuned by eye; refine in-headset.
const FACE_PRESS: float    = 0.0022
const TRIGGER_PRESS: float = 0.0032
const SMALL_PRESS: float   = 0.0016
const STICK_CLICK: float   = 0.0016
const DPAD_TILT_DEG: float  = 7.0
const STICK_TILT_DEG: float = 16.0
const PRESS_DIR: Vector3   = Vector3(0, -1, 0)   # "into the shell" in model space
const ANIM_LERP: float     = 20.0

# The animation engine, shared with the handheld models — a handheld's built-in
# face is the same problem as a pad's. The bindings below are views onto it, so a
# subclass's _cache_meshes() fills them exactly as it always did.
var _anim := ControlAnimator.new()
# The same controls, pressed with a fingertip (see ControlPoke). Built from _anim
# after _cache_meshes(), so a pad's caps are pokeable exactly where they move.
var _poke: ControlPoke = null

# Cached animated meshes. Each button entry: {node, rest, bit, depth}.
@warning_ignore("unused_private_class_variable")
var _buttons: Array[Dictionary]:
	get: return _anim.buttons
	set(v): _anim.buttons = v
# D-pad / sticks: {node, rest, pivot} (pivot in the mesh's parent space).
@warning_ignore("unused_private_class_variable")
var _dpad: Dictionary:
	get: return _anim.dpad
	set(v): _anim.dpad = v
# A second rocker, for pads with two D-pads (the Virtual Boy). Same shape as
# _dpad plus "bits" [up, down, left, right] and an optional "axis" ("left" /
# "right") folding that analog stick in — a second D-pad has no RetroPad bits of
# its own, so which ones it borrows is the core's choice.
@warning_ignore("unused_private_class_variable")
var _dpad2: Dictionary:
	get: return _anim.dpad2
	set(v): _anim.dpad2 = v
@warning_ignore("unused_private_class_variable")
var _stick_l: Dictionary:
	get: return _anim.stick_l
	set(v): _anim.stick_l = v
@warning_ignore("unused_private_class_variable")
var _stick_r: Dictionary:
	get: return _anim.stick_r
	set(v): _anim.stick_r = v

# Latest joypad state captured from _send_joypad; zeroed when no input this frame.
var _cur_btn: int = 0
var _cur_lstick: Vector2 = Vector2.ZERO
var _cur_rstick: Vector2 = Vector2.ZERO
var _got_input: bool = false


func _ready() -> void:
	super._ready()
	_cache_meshes()
	_bind_poke()


## Every animated control becomes a poke target, plus any the pad adds itself.
func _bind_poke() -> void:
	# Which arm of the cross is UP is the pitch sign's, which _animate only hands
	# the animator on its first frame — the poke reads it now.
	_anim.dpad_pitch_sign = _dpad_pitch_sign()
	_poke = ControlPoke.new(self)
	_poke.add_animator(_anim)
	_poke.targets.append_array(_extra_poke_targets())


## Controls this pad moves outside the animator (a trigger it swings itself, a
## cap with no input behind it), as ControlPoke targets — see ControlPoke for the
## shape. Its own hook, so a pad pack overrides it with no super() to call, which
## a pack still loading in an older build could not do.
func _extra_poke_targets() -> Array[Dictionary]:
	return []


# ── Node caching ────────────────────────────────────────────────────────────

## Bind this pad's moving meshes into _buttons / _dpad / _dpad2 / _stick_l /
## _stick_r. Imported models search by mesh name (_find_mesh); pads authored as
## primitives look their controls up by node path.
func _cache_meshes() -> void:
	pass


# Normalise a node name for tolerant matching (Godot's glTF import may turn
# "button_x.002" into "button_x_002" / "button_x002"). Strips non-alphanumerics.
func _norm(s: String) -> String:
	var out: String = ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


func _find_mesh(base: String) -> MeshInstance3D:
	var target: String = _norm(base)
	for n: Node in find_children("*", "MeshInstance3D", true, false):
		if _norm(n.name).begins_with(target):
			return n as MeshInstance3D
	return null


# Find a non-mesh marker node by exact normalised name (a shell's pivot empties).
func _find_pivot(mesh: MeshInstance3D, empty_name: String) -> Vector3:
	if mesh == null:
		return Vector3.ZERO
	var target: String = _norm(empty_name)
	for n: Node in find_children("*", "Node3D", true, false):
		if n is MeshInstance3D:
			continue
		if _norm(n.name) == target:
			var n3d: Node3D = n as Node3D
			return mesh.get_parent().to_local(n3d.global_position)
	# No pivot empty (e.g. the PS2 model ships none) — fall back to the mesh's
	# own AABB centre so sticks/D-pad still rotate in place, not about the origin.
	var a: AABB = mesh.get_aabb()
	return mesh.transform * a.get_center()


## How far the "d-pad" rocks about its pivot. A flat pad only needs a few
## degrees; a real joystick shaft swings much further. Override per controller.
func _dpad_tilt_deg() -> float:
	return DPAD_TILT_DEG


## Sign of the D-pad's pitch rotation. A positive pitch about the mesh parent's
## X axis lifts whatever lies on -Z, so a model whose UP arm points -Z must
## return -1.0 for UP to depress it. Roll is unaffected.
func _dpad_pitch_sign() -> float:
	return 1.0


# ── Input capture + animation ───────────────────────────────────────────────

# Capture the exact merged per-frame state, then forward to the base behaviour.
# A poked cap joins here, so the core, netplay and the animation all see it.
func _send_joypad(btn: int, alx: int, aly: int, arx: int, ary: int) -> void:
	if _poke != null:
		var m := _poke.merge_into(btn, alx, aly, arx, ary, ANALOG_SCALE)
		btn = m["btn"]; alx = m["alx"]; aly = m["aly"]; arx = m["arx"]; ary = m["ary"]
	_cur_btn = btn
	_cur_lstick = Vector2(float(alx) / ANALOG_SCALE, float(aly) / ANALOG_SCALE)
	_cur_rstick = Vector2(float(arx) / ANALOG_SCALE, float(ary) / ANALOG_SCALE)
	_got_input = true
	super._send_joypad(btn, alx, aly, arx, ary)


func _process(delta: float) -> void:
	_got_input = false
	super._process(delta)          # runs hold/drop/plug logic; calls _send_joypad when active
	if not _got_input:             # not plugged/held → relax to rest
		# A pad plugged into nothing still gives under a finger: the cap moves,
		# there is just no core to tell.
		var s: Dictionary = _poke.poll() if _poke != null else {}
		_cur_btn = int(s.get("btn", 0))
		_cur_lstick = s.get("lstick", Vector2.ZERO)
		_cur_rstick = s.get("rstick", Vector2.ZERO)
	_animate(delta)


func _animate(delta: float) -> void:
	_anim.dpad_tilt_deg = _dpad_tilt_deg()
	_anim.dpad_pitch_sign = _dpad_pitch_sign()
	_anim.animate(_cur_btn, _cur_lstick, _cur_rstick, clampf(ANIM_LERP * delta, 0.0, 1.0))
