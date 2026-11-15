## The colours a loudspeaker comes in: the satellite, the subwoofer and the computer pair.
##
## A finish is the SAME model in another colour (RetroXR-models common/applkit/speakers.py
## "finishes"): every node, marker, size and level is the black build's, so a finish only
## swaps the ApplianceModel's level scenes for the files of that finish, which carry it in
## their names before the level (`computer_left_mobile_lod1.glb` ->
## `computer_left_beige_mobile_lod1.glb`). Nothing a cabinet dresses from its model moves.
##
## The finish is the object's `model_variant` (SystemModelRegistry.VARIANT_KEY), so the save,
## object sync and the spawn menu's held-row colours carry it with no code of their own. It
## must be set before the object enters the tree: ApplianceModel builds its levels in _ready.
class_name SpeakerFinish
extends RefCounted

## The rows' colours, the first being the model as it comes (a plain press spawns it).
const VARIANTS: Array = [
	{"id": "black", "label": "Black", "color": Color8(26, 26, 28)},
	# The 1990s computer beige: generic/pc-tower's case plastic, so a set beside the
	# tower reads as the one that came with it.
	{"id": "beige", "label": "Beige", "color": Color8(209, 197, 168)},
]

## The finishes with files of their own (black is the plain files).
const FINISHES: Array[String] = ["beige"]


## Put `model` in `finish` ("" or "black" for the plain files). Safe to call again: the
## plain path is recovered from whatever the model wears now.
static func apply(model: ApplianceModel, finish: String, who: Node) -> void:
	var tag := str(who.name) if who != null else "?"
	if model == null:
		push_warning("[Speaker] %s: no Model to put in the '%s' finish" % [tag, finish])
		return
	if model.is_node_ready():
		# Its levels are built: a late finish would leave the dressing on the old meshes.
		push_warning("[Speaker] %s: finish '%s' asked for after the model was built; ignored" % [tag, finish])
		return
	var wanted := "" if finish == "black" else finish
	if not wanted.is_empty() and not FINISHES.has(wanted):
		push_warning("[Speaker] %s: unknown finish '%s', staying as it comes" % [tag, finish])
		wanted = ""
	var out: Array[PackedScene] = []
	for scene: PackedScene in model.level_scenes:
		var path := path_in(plain_path(scene.resource_path), wanted)
		if path == scene.resource_path:
			out.append(scene)
		elif ResourceLoader.exists(path):
			out.append(load(path) as PackedScene)
		else:
			push_warning("[Speaker] %s: no '%s' file %s; that level stays as it was" % [tag, wanted, path])
			out.append(scene)
	model.level_scenes = out
	print("[Speaker] %s: finish %s" % [tag, wanted if not wanted.is_empty() else "black (as it comes)"])


## A level file's path in `finish`: the finish goes before the level (`_mobile`).
static func path_in(plain: String, finish: String) -> String:
	if finish.is_empty():
		return plain
	var at := plain.rfind("_mobile")
	return plain if at < 0 else plain.substr(0, at) + "_" + finish + plain.substr(at)


## The plain file a level path is a finish of.
static func plain_path(path: String) -> String:
	for finish: String in FINISHES:
		path = path.replace("_%s_mobile" % finish, "_mobile")
	return path
