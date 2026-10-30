## DeckFace — what the RETRO XR VCR and DVD player do to dress their scenes with their models (ApplianceModel):
## keys on the FRONT panel, phono sockets on the model's jacks, and the model's contract (the per-frame poses its
## animations carry, exported beside the GLBs as <item>_contract.json).
class_name DeckFace
extends RefCounted

## A key's press, in meters (the models' `travel_m`).
const KEY_TRAVEL := 0.0015
## A phono socket's zone stands where a seated plug's origin belongs, 10 mm proud of the panel (rca_port.tscn);
## the models' port empties are at the jack's mouth, 9 mm out.
const PORT_PROUD := 0.001


## Dress `button` with the model's key `part`, keeping the VRButton convention every other cap follows: the cap
## faces its node's +Y and presses along -Y. ApplianceModel.adopt_button leaves the key's own frame (a front key
## faces +Z), so the node is turned a quarter about X and the cap and its box are turned back inside it, which
## leaves them where they were. The combo-set code and its tests read a key's facing off that +Y.
static func adopt_front_key(model: ApplianceModel, button: VRButton, part: String) -> void:
	model.adopt_button(button, part, KEY_TRAVEL)
	var r := Basis(Vector3.RIGHT, PI / 2.0)
	button.transform = Transform3D(button.transform.basis * r, button.transform.origin)
	var cap: MeshInstance3D = null
	for child in button.get_children():
		if child is CollisionShape3D or (child is MeshInstance3D and child.name == "ButtonMesh"):
			(child as Node3D).transform = Transform3D(r.inverse(), Vector3.ZERO) * (child as Node3D).transform
			if child.name == "ButtonMesh":
				cap = child as MeshInstance3D
	button.depress_axis = Vector3(0, -1, 0)
	if cap != null:
		# Re-recorded in its turned frame. set_button_mesh hides whatever is named ButtonMesh, which IS this cap.
		button.set_button_mesh(cap)
		cap.visible = true


## Put a phono socket on the model's jack `part` (its empty at the mouth, local +Z out of the panel), the zone
## 1 mm further out, and leave the jack to the model.
static func seat_port(model: ApplianceModel, port: Node3D, part: String) -> void:
	var t := model.part_transform(part, port.get_parent() as Node3D)
	port.transform = t.translated_local(Vector3(0.0, 0.0, PORT_PROUD))
	if "show_jack" in port:
		port.set("show_jack", false)


## The model's contract JSON, or {} (logged) when it cannot be read.
static func contract(path: String, tag: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not parsed is Dictionary:
		push_warning("[%s] the model's contract %s could not be read" % [tag, path])
		return {}
	return parsed as Dictionary


## One field of a contract's per-frame table (`rows`: [{frame, ...}]) at time `t` seconds, linear between frames.
static func sample(rows: Array, t: float, fps: float, key: String) -> Variant:
	if rows.is_empty():
		return null
	var f := clampf(t * fps, 0.0, float(rows.size() - 1))
	var i := floori(f)
	var j := mini(i + 1, rows.size() - 1)
	var a: Variant = (rows[i] as Dictionary).get(key)
	var b: Variant = (rows[j] as Dictionary).get(key)
	var w := f - float(i)
	if a is Array:
		var va := Vector3(a[0], a[1], a[2])
		var vb := Vector3(b[0], b[1], b[2])
		return va.lerp(vb, w)
	return lerpf(float(a), float(b), w)


## A [x, deg] table (the VCR's door_vs_tape) read at x, clamped to its ends.
static func lookup(rows: Array, x: float) -> float:
	if rows.is_empty():
		return 0.0
	if x <= float(rows[0][0]):
		return float(rows[0][1])
	for k in range(1, rows.size()):
		if x <= float(rows[k][0]):
			var x0 := float(rows[k - 1][0])
			var x1 := float(rows[k][0])
			return lerpf(float(rows[k - 1][1]), float(rows[k][1]), (x - x0) / maxf(x1 - x0, 1e-9))
	return float(rows[-1][1])
