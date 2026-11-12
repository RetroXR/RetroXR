## ArcadeBayShells — a mod's model worn by an arcade bay (ArcadeBayUnit) in place of the look the game baked.
##
## The game ships every bay kind as a stand-in (Tools/gen/gen_arcade_bay.gd): a box of the right size with
## the seat and the sockets where the real board has them, so a board plays with no mod at all. A mod that
## models the real board (the NAOMI, say) hands its GLB here, through ModApi.override_arcade_bay_shell, and
## every bay of that kind wears it: the stand-in's meshes and labels are hidden, the model is fitted to
## `size` the way an expansion's shell is (RetroExpansion._build_shell), and what the bay DOES stays the
## game's: its collision, its pointer box, its grab point, its slot and its ports.
##
## The model moves the bay's markers. The seat and the sockets are markers in the baked scene (CartSeat,
## DiscSeat, VgaAnchor, JvsAnchor ...); where the model has a node of the marker's name (or, for the two
## seats, CartAnchor and DiscAnchor, the models repo's names) the marker is moved onto it, keeping its own
## turn. So a model whose socket is a few millimetres from the stand-in's still takes its cord there.
##
## A row (fields): shell (a model path, required), size (the model's true bounds in metres, required),
## shell_lods ([[model path, metres], ...], nearest first), shell_offset (moves the fitted model off the
## middle of the bay's box). One mod per kind; withdrawn with its mod. Local and cosmetic: never saved.
class_name ArcadeBayShells
extends RefCounted

## The fields a row may set, and their types.
## `origin`: a model drawn true to size in the object's own frame is placed by it instead of fitted: the model's point at
## `origin` goes on the object's origin, unscaled; `turn` turns a model drawn in another frame (a Z-up model on a
## +Y-up object: Basis(Vector3.RIGHT, -PI / 2)) about that point.
const _FIELDS := {"shell": TYPE_STRING, "size": TYPE_VECTOR3, "shell_lods": TYPE_ARRAY, "shell_offset": TYPE_VECTOR3, "origin": TYPE_VECTOR3, "turn": TYPE_BASIS}

## A bay marker -> the model's node it moves onto, where the names differ.
const SEAT_ANCHORS := {"CartSeat": "CartAnchor", "DiscSeat": "DiscAnchor"}

## The other boards a mod can dress the same way: the JVS-to-JAMMA converter (JvsJammaConverter) and a JVS cabinet's
## I/O board (ArcadeCabinetFromModel draws its stand-in at the cabinet's JvsLead).
const OTHER_KINDS := {"jvs_jamma_converter": "Sega JVS-to-JAMMA converter", "jvs_io_board": "Sega JVS I/O board",
	"naomi_dimm_board": "Sega NAOMI DIMM board", "naomi_gd_drive": "Sega NAOMI GD-ROM drive", "naomi_key": "Sega NAOMI key chip"}

## How far past a level's switch distance the next one waits before switching back (metres).
const LOD_HYSTERESIS := 0.1

## bay kind -> {"owner": mod id, "fields": the checked row}.
static var _rows: Dictionary = {}


## Validate and keep a mod's model for `kind`. Returns "" or what is wrong with it.
static func register_mod_shell(kind: String, fields: Dictionary, owner_id: String) -> String:
	if not ArcadeBayUnit.SCENES.has(kind) and not OTHER_KINDS.has(kind):
		return "'%s' is not an arcade bay kind (%s)" % [kind, ", ".join(PackedStringArray(ArcadeBayUnit.SCENES.keys() + OTHER_KINDS.keys()))]
	var holder := owner_of(kind)
	if not holder.is_empty() and holder != owner_id:
		return "the %s bay's model already comes from mod '%s'" % [kind, holder]
	var checked := {}
	for key: Variant in fields:
		if not _FIELDS.has(key):
			return "'%s' is not something a bay's model can set (%s)" % [key, ", ".join(PackedStringArray(_FIELDS.keys()))]
		if typeof(fields[key]) != _FIELDS[key]:
			return "%s is the wrong type" % key
		checked[key] = fields[key]
	if not checked.has("shell") or not ResourceLoader.exists(str(checked["shell"])):
		return "shell does not exist: %s" % str(checked.get("shell", ""))
	var size: Variant = checked.get("size", Vector3.ZERO)
	if not (size is Vector3) or (size as Vector3).x <= 0.0 or (size as Vector3).y <= 0.0 or (size as Vector3).z <= 0.0:
		return "size is required: the model's true bounds, in metres"
	for level: Variant in checked.get("shell_lods", []):
		if not (level is Array) or (level as Array).size() != 2 or not ResourceLoader.exists(str((level as Array)[0])):
			return "a shell_lods entry is [model path, metres], and its model must exist"
	_rows[kind] = {"owner": owner_id, "fields": checked}
	return ""


static func owner_of(kind: String) -> String:
	return str((_rows.get(kind, {}) as Dictionary).get("owner", ""))


static func has_shell(kind: String) -> bool:
	return _rows.has(kind)


static func drop_mod(owner_id: String) -> void:
	for kind: String in _rows.keys():
		if _rows[kind]["owner"] == owner_id:
			_rows.erase(kind)


## Put the mod's model on `bay` (in the tree, before it builds its slot): hide the stand-in's look, fit the
## model to the bay's box, give it its levels, and move the markers onto the model's nodes. Returns the
## model's root, or null when the kind has no model (the stand-in stays as it is).
static func dress(bay: Node3D, kind: String, _box: Vector3) -> Node3D:
	if not _rows.has(kind):
		return null
	var f: Dictionary = _rows[kind]["fields"]
	var packed := load(str(f["shell"])) as PackedScene
	if packed == null:
		push_warning("[ArcadeBay] the %s bay's model could not be loaded: %s" % [kind, f["shell"]])
		return null
	var shell := packed.instantiate() as Node3D
	if shell == null:
		return null
	shell.name = "Shell"
	bay.add_child(shell)
	var ab := _mesh_bounds(shell)
	if ab.size.x <= 0.0001 or ab.size.y <= 0.0001 or ab.size.z <= 0.0001:
		shell.queue_free()
		return null
	var size: Vector3 = f["size"]
	var k := Vector3(size.x / ab.size.x, size.y / ab.size.y, size.z / ab.size.z)
	shell.scale = k
	# The bay's origin is on the floor at the middle of its base: the model stands on the floor, its plan
	# centred on the bay's (a model taller than the stand-in's box, its sockets proud of the front, still stands).
	var mid := ab.position + ab.size * 0.5
	shell.position = Vector3(-mid.x * k.x, -ab.position.y * k.y, -mid.z * k.z) + (f.get("shell_offset", Vector3.ZERO) as Vector3)
	if f.has("origin"):
		var turn: Basis = f.get("turn", Basis.IDENTITY)
		shell.transform = Transform3D(turn, -(turn * (f["origin"] as Vector3)))
	_hide_stand_in(bay, shell)
	_levels(bay, shell, f.get("shell_lods", []) as Array)
	_move_markers(bay, shell)
	return shell


## The stand-in's own look: every mesh and label not under a node with a script of its own (a port, a
## button, the highlight: those still work and still show) and not in the model.
static func _hide_stand_in(bay: Node3D, shell: Node3D) -> void:
	for n in bay.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if shell.is_ancestor_of(g):
			continue
		var p := g.get_parent()
		var scripted := false
		while p != null and p != bay:
			if p.get_script() != null:
				scripted = true
				break
			p = p.get_parent()
		if not scripted:
			g.visible = false


static func _levels(bay: Node3D, shell: Node3D, lods: Array) -> void:
	if lods.is_empty():
		return
	var levels: Array[Node3D] = [shell]
	var starts: Array[float] = [0.0]
	for entry: Array in lods:
		var packed := load(str(entry[0])) as PackedScene
		if packed == null:
			continue
		var level := packed.instantiate() as Node3D
		level.name = "ShellLOD%d" % levels.size()
		level.transform = shell.transform
		bay.add_child(level)
		levels.append(level)
		starts.append(float(entry[1]))
	for i in levels.size():
		var begin: float = starts[i]
		var end: float = starts[i + 1] if i + 1 < levels.size() else 0.0
		for n in levels[i].find_children("*", "GeometryInstance3D", true, false):
			var g := n as GeometryInstance3D
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			# No margins: with fading off, a margin on the next level's begin left a band (0.8 to 0.9 m) where neither
			# level drew -- the GD-ROM drive vanished there in a video of the hookup.
			g.visibility_range_begin = begin
			g.visibility_range_begin_margin = 0.0
			g.visibility_range_end = end
			g.visibility_range_end_margin = 0.0


## Each of the bay's markers (its seats, its sockets' anchors) onto the model's node of that name, keeping
## the marker's own turn: the model says where, the game says which way a cartridge or a plug goes in.
static func _move_markers(bay: Node3D, shell: Node3D) -> void:
	var to_bay := bay.global_transform.affine_inverse()
	for n in bay.find_children("*", "Marker3D", true, false):
		var m := n as Marker3D
		if shell.is_ancestor_of(m):
			continue
		var want := str(SEAT_ANCHORS.get(m.name, m.name))
		if not want.ends_with("Anchor"):
			continue
		var at := shell.find_child(want, true, false) as Node3D
		if at == null:
			continue
		var p := to_bay * at.global_position
		var parent := m.get_parent() as Node3D
		m.position = (parent.global_transform.affine_inverse() * (bay.global_transform * p)) if parent != null else p


## Bounds of every mesh under `root`, in `root`'s own space.
static func _mesh_bounds(root: Node3D) -> AABB:
	var to_root := root.global_transform.affine_inverse()
	var acc := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var ab: AABB = (to_root * mi.global_transform) * mi.get_aabb()
		acc = ab if first else acc.merge(ab)
		first = false
	return acc
