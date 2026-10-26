## SnesMouse — the Super NES Mouse (SNS-016), as shipped with Mario Paint.
##
## Everything that makes a mouse a mouse — the sticky surface, the delta
## reporting, the cable, the port handshake, the settings panel — is RetroMouse's
## and is inherited unchanged. This subclass exists for the three things the real
## hardware does differently from the primitive stand-in:
##
##   * it has TWO buttons, not three, so no middle click is ever reported;
##   * its buttons are the whole front half of the shell, hinged at the back,
##     rather than caps that sink into it;
##   * it fits only a Super NES (systemid + its own connector, set in the scene).
class_name SnesMouse
extends RetroMouse


## How far the FRONT TIP of a button travels at full press. The pivot angle is
## derived from this and the button's own length, so re-exporting a shell with
## differently-sized buttons keeps the same visible throw instead of silently
## rescaling it.
##
## Capped by the model, not by taste. The cap is nearly flush: measured against
## the shell beside it, it stands 0.21 mm proud at the hinge, 0.76 mm at
## mid-length and 0.61 mm three-quarters along, only flaring to 3.25 mm at the
## nose. A rear hinge drops the cap in proportion to the distance from the hinge
## while that clearance does NOT grow to match, so the tightest point — the
## three-quarter mark — sets the limit at about 0.8 mm. A real mouse button's
## 1.5 mm sank the middle of the paddle under a shell that is continuous
## underneath, and the button rendered as two purple stubs with grey between.
const TIP_DROP: float = 0.0006


## Add the hinge to each cached button: the pivot (its top rear edge, in the
## mesh's parent space) and the arm length out to the tip.
func _cache_buttons() -> void:
	super._cache_buttons()
	for e: Dictionary in _anim_btns:
		var node: MeshInstance3D = e["node"]
		if node.mesh == null:
			continue
		var rest: Transform3D = e["rest"]
		var ab: AABB = node.mesh.get_aabb()
		# Front is -Z, so the hinge is the far edge: max Z, at the shell surface.
		e["pivot"] = rest * Vector3(ab.get_center().x, ab.end.y, ab.end.z)
		e["arm"] = ab.size.z


## Rock the button about its rear hinge. Sinking it bodily — RetroMouse's default
## — would drop the panel below the shell it is flush with and open a slot along
## the hinge line, because on this mouse the button IS the front of the shell.
func _button_pose(entry: Dictionary, down: float) -> Transform3D:
	var rest: Transform3D = entry["rest"]
	var arm: float = entry.get("arm", 0.0)
	if arm <= 0.0:
		return super._button_pose(entry, down)
	var pivot: Vector3 = entry["pivot"]
	# Negative: a positive turn about +X lifts what lies on -Z, and the tip is
	# the -Z end.
	var tilt := Basis(Vector3.RIGHT, -atan(TIP_DROP / arm) * down)
	return Transform3D(tilt * rest.basis, pivot + tilt * (rest.origin - pivot))


## Two buttons. The libretro mouse device carries a middle button and RetroMouse
## binds one, but this shell has nothing to press for it, so reporting it would
## hand the core an input the hardware cannot produce.
func _poll_buttons() -> int:
	return super._poll_buttons() & ~MOUSE_BTN_MIDDLE
