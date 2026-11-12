## RetroPadController — the universal RetroXR pad (retro_controller.tscn).
##
## It wears RetroXR's own RETRO XR pad (RetroXR-models generic/retropad), baked one
## mesh per node into the scene, so every control keeps the path and origin it had
## as a primitive. It comes in three colourways (COLOURWAYS), a spawn-menu colour
## like a console shell's. It carries the complete libretro
## joypad: a rocking D-pad (UP/DOWN/LEFT/RIGHT), the A/B/X/Y face diamond,
## SELECT/START, L/R shoulders, L2/R2 triggers and two analog sticks that also
## click (L3/R3) — all 16 buttons plus both axes.
##
## Animation is AnimatedController's engine. Because the meshes are authored
## here rather than imported, controls are bound by node path instead of the
## fuzzy mesh-name search the console models need.
class_name RetroPadController
extends AnimatedController

# Node path (from the pad root) -> RETRO_JOYPAD bit.
const PAD_FACE: Dictionary = {
	"Model/FaceB": ControllerBindings.JOYPAD_B,
	"Model/FaceA": ControllerBindings.JOYPAD_A,
	"Model/FaceY": ControllerBindings.JOYPAD_Y,
	"Model/FaceX": ControllerBindings.JOYPAD_X,
}
const PAD_SMALL: Dictionary = {
	"Model/Select": ControllerBindings.JOYPAD_SELECT,
	"Model/Start":  ControllerBindings.JOYPAD_START,
}
const PAD_EDGE: Dictionary = {
	"Model/ShoulderL": ControllerBindings.JOYPAD_L,
	"Model/ShoulderR": ControllerBindings.JOYPAD_R,
	"Model/TriggerL":  ControllerBindings.JOYPAD_L2,
	"Model/TriggerR":  ControllerBindings.JOYPAD_R2,
}

## The colourways: the shell's top, bottom and the seam line between them, in that
## surface order (PAD_Top, PAD_Bottom, PAD_Seam). sRGB 0-255, as pad_contract.json
## lists them. The first is the model's own and the default. Offered on the spawn
## menu's controller row (SpawnCatalog.RETROPAD_VARIANTS) and saved by the room as
## any object's model_variant.
const COLOURWAYS: Dictionary = {
	"charcoal": [Color8(44, 44, 47), Color8(224, 214, 194), Color8(236, 122, 34)],
	"cream":    [Color8(226, 218, 200), Color8(46, 64, 72), Color8(112, 196, 112)],
	"red":      [Color8(150, 50, 44), Color8(224, 214, 194), Color8(236, 226, 206)],
}

## The colourway it wears (a COLOURWAYS key; "" is the default). Set before the pad
## enters the room (SystemModelRegistry.set_variant_of), or at any time after.
var model_variant: String = "":
	set(v):
		model_variant = v
		if is_node_ready():
			_apply_colourway()


func _apply_colourway() -> void:
	var shell := get_node_or_null("Model/Shell") as MeshInstance3D
	if shell == null or shell.mesh == null:
		return
	if model_variant.is_empty():
		for i in shell.mesh.get_surface_count():
			shell.set_surface_override_material(i, null)
		return
	var colours: Array = COLOURWAYS.get(model_variant, [])
	if colours.is_empty():
		# Not one of ours: a mod that offers colours for this row paints them itself (it reads the same
		# model_variant), so the shell is left as the mod leaves it.
		print("[RetroPadController] %s: colour '%s' is not a RETRO XR colourway, left to whoever offered it"
			% [name, model_variant])
		return
	for i in mini(colours.size(), shell.mesh.get_surface_count()):
		var mat := shell.mesh.surface_get_material(i)
		var own := (mat.duplicate() if mat != null else StandardMaterial3D.new()) as BaseMaterial3D
		own.albedo_color = colours[i]
		shell.set_surface_override_material(i, own)
	print("[RetroPadController] %s wears the %s colourway" % [name, model_variant])


## Shoulders and triggers are mounted on the far face (-Z) and travel into it,
## not down into the top surface like the face buttons.
const EDGE_DIR := Vector3.BACK

## The D-pad and sticks rock about the shell surface, which sits below each
## control's own origin by these amounts.
const DPAD_PIVOT_DROP:  float = 0.003
const STICK_PIVOT_DROP: float = 0.0055


func _ready() -> void:
	super._ready()
	_apply_colourway()


func _cache_meshes() -> void:
	_anim.buttons.clear()
	for path: String in PAD_FACE:
		_add_button(path, int(PAD_FACE[path]), FACE_PRESS, PRESS_DIR)
	for path: String in PAD_SMALL:
		_add_button(path, int(PAD_SMALL[path]), SMALL_PRESS, PRESS_DIR)
	for path: String in PAD_EDGE:
		_add_button(path, int(PAD_EDGE[path]), TRIGGER_PRESS, EDGE_DIR)
	_anim.dpad    = _pivoted_control("Model/DPad", DPAD_PIVOT_DROP)
	_anim.stick_l = _pivoted_control("Model/StickL", STICK_PIVOT_DROP)
	_anim.stick_r = _pivoted_control("Model/StickR", STICK_PIVOT_DROP)


## The authored D-pad's UP arm points -Z (away from the holder, the edge the
## cable and shoulders sit on), so the engine's default pitch would lift it.
func _dpad_pitch_sign() -> float:
	return -1.0


func _add_button(path: String, bit: int, depth: float, dir: Vector3) -> void:
	var m := get_node_or_null(path) as MeshInstance3D
	if m == null:
		push_warning("[RetroPadController] control mesh not found: " + path)
		return
	_anim.buttons.append({"node": m, "rest": m.transform, "bit": bit, "depth": depth, "dir": dir})


func _pivoted_control(path: String, drop_dist: float) -> Dictionary:
	var m := get_node_or_null(path) as MeshInstance3D
	if m == null:
		push_warning("[RetroPadController] control mesh not found: " + path)
		return {}
	return {"node": m, "rest": m.transform, "pivot": m.position - Vector3(0.0, drop_dist, 0.0)}
