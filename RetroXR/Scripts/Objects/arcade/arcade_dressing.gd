## ArcadeDressing — a mod's look laid over the Morphing Arcade Cabinet's own parts, by part NAME,
## after every build: the baked scene when it arrives, and every form it takes for the game in its bay.
##
## A cabinet a mod draws for itself (ModApi.register_model / override_model on a shipped id) keeps the
## form it has: it names no row, so it cannot morph ("How a form changes", docs/dev/arcade.md). A
## dressing is the other way round: the cabinet goes on building itself (ArcadeCabinetBuilder) and the
## mod repaints, hides or adds to what it built, so it still grows guns, panels and a cockpit for the
## game. The part names are the builder's own (Btn1, SideL, Marquee, StickBall, DriverSeat ...), the
## same ones the modules and the hands find a part by, so they do not move.
##
## A row (ModApi.dress_arcade_cabinet, docs/modding.md "Dressing the arcade cabinet"):
##   variants  ["generic", "neogeo", ...]: the cabinets it dresses, by the row each was baked from
##             (ArcadeCabinetSpecs.variants); "" is a cabinet that names none (a mod's own). Empty or
##             missing = every cabinet.
##   shapes    ["upright", "wide", ...]: only forms of these shapes (ArcadeCabinetSpecs.shapes). Empty = all.
##   colors    {group or part name: Color or "#rrggbb"}: a plain material of that colour.
##   materials {group or part name: Material or a res:// path to one}.
##   hide      [part names]: drawn no more; the node stays (a module, the hands and the art find it).
##   parts     {part name: a res:// .tscn}: instanced under that part, at its origin and in its frame,
##             which is the cabinet's (+Z out of the front, +Y up); a box part's origin is its centre.
## Groups name the builder's shared paints: "body", "trim", "dark". Anything else is a part name, and
## every part of that name is dressed (each player's Btn1).
##
## Cosmetic and local: never saved, never on the wire. Withdrawn with its mod; a cabinet already
## standing keeps the dressing until it is next built (a mod switching off reloads the room).
class_name ArcadeDressing
extends RefCounted

## The parts each group of the builder's paints covers (ArcadeCabinetBuilder._body/_trim/_dark).
const GROUPS := {
	"body": ["SideL", "SideR", "Rear", "Top", "Floor", "CoinFace", "LowerFaceL", "LowerFaceR",
		"ApronUnder", "Apron", "HoodFront"],
	"trim": ["ApronTrim", "MarqueeTrim", "HoodTrim"],
	"dark": ["KickPlate", "MarqueeUnder", "HoodUnder"],
}

## The child a dressing's scene is instanced as, so a rebuild that keeps the part (the bay is never
## rebuilt by a morph) does not instance it twice.
const PART_PREFIX := "ModDress_"
## The mesh a hidden part had, kept on the node.
const HIDDEN_META := &"arcade_dress_hidden_mesh"

## dressing id -> {"row": the validated row, "owner": mod id}. Applied in id order, so two mods
## dressing one part always settle the same way.
static var _rows: Dictionary = {}


## Validate and keep a dressing. Returns "" or what is wrong with it.
static func register(dress_id: String, row: Dictionary, owner_id: String) -> String:
	for key: String in row:
		if not key in ["variants", "shapes", "colors", "materials", "hide", "parts"]:
			return "unknown field '%s'" % key
	var shapes := ArcadeCabinetSpecs.shapes()
	for s: Variant in row.get("shapes", []):
		if not shapes.has(str(s)):
			return "no cabinet shape '%s' (one of %s)" % [s, ", ".join(PackedStringArray(shapes.keys()))]
	var known := ArcadeCabinetSpecs.variants()
	for v: Variant in row.get("variants", []):
		if str(v) != "" and not known.has(str(v)):
			return "no cabinet variant '%s' (one of %s, or \"\")" % [v, ", ".join(PackedStringArray(known.keys()))]
	var clean := row.duplicate(true)
	var paints := {}
	for name: String in (row.get("colors", {}) as Dictionary):
		var c: Variant = row["colors"][name]
		var color: Color
		if c is Color:
			color = c
		elif c is String and Color.html_is_valid(c):
			color = Color.html(c)
		else:
			return "colors.%s is not a Color or \"#rrggbb\"" % name
		paints[name] = ArcadeParts.mat(color, 0.0, 0.55)
	for name: String in (row.get("materials", {}) as Dictionary):
		var m: Variant = row["materials"][name]
		if m is String:
			if not ResourceLoader.exists(m):
				return "materials.%s: no resource at %s" % [name, m]
			m = load(m)
		if not m is Material:
			return "materials.%s is not a Material" % name
		paints[name] = m
	clean["paints"] = paints
	for name: String in (row.get("parts", {}) as Dictionary):
		var path := str(row["parts"][name])
		if not ResourceLoader.exists(path):
			return "parts.%s: no scene at %s" % [name, path]
	_rows[dress_id] = {"row": clean, "owner": owner_id}
	print("[ArcadeDressing] %s registered by %s: %d paint(s), %d hidden, %d part(s)" % [dress_id, owner_id,
		paints.size(), (row.get("hide", []) as Array).size(), (row.get("parts", {}) as Dictionary).size()])
	return ""


static func drop_mod(owner_id: String) -> void:
	for dress_id: String in _rows.keys():
		if str(_rows[dress_id]["owner"]) == owner_id:
			_rows.erase(dress_id)
			print("[ArcadeDressing] %s withdrawn with %s" % [dress_id, owner_id])


## The dressings a cabinet baked from `variant` takes in a form of `shape`, in the order they apply.
static func matching(variant: String, shape: String) -> Array[String]:
	var out: Array[String] = []
	var ids := _rows.keys()
	ids.sort()
	for dress_id: String in ids:
		var row: Dictionary = _rows[dress_id]["row"]
		var variants: Array = row.get("variants", [])
		if not variants.is_empty() and not variants.has(variant):
			continue
		var shapes: Array = row.get("shapes", [])
		if not shapes.is_empty() and not shapes.has(shape):
			continue
		out.append(dress_id)
	return out


## Dress `cabinet` (the model's root) as it stands, built from `spec` (its form's, or {} for a cabinet that
## names no row). Safe to call again after a morph: a scene already instanced under a part is left.
static func apply(cabinet: Node3D, variant: String, spec: Dictionary) -> void:
	if _rows.is_empty():
		return
	var shape := str(spec.get("shape", "upright"))
	var ids := matching(variant, shape)
	if ids.is_empty():
		return
	var by_name := _parts_by_name(cabinet)
	for dress_id in ids:
		var row: Dictionary = _rows[dress_id]["row"]
		var painted := 0
		var missing := PackedStringArray()
		for name: String in (row["paints"] as Dictionary):
			var targets: Array = GROUPS.get(name, [name])
			var hit := false
			for part: String in targets:
				for node: Node in by_name.get(part, []):
					if node is MeshInstance3D:
						_paint(node as MeshInstance3D, row["paints"][name])
						painted += 1
						hit = true
			if not hit and not GROUPS.has(name):
				missing.append(name)
		for name: Variant in row.get("hide", []):
			for node: Node in by_name.get(str(name), []):
				if node is MeshInstance3D and not node.has_meta(HIDDEN_META):
					var mi := node as MeshInstance3D
					mi.set_meta(HIDDEN_META, mi.mesh)
					mi.mesh = null
		var added := 0
		for name: String in (row.get("parts", {}) as Dictionary):
			var child_name := PART_PREFIX + dress_id.replace(":", "_")
			var at: Array = by_name.get(name, [])
			if at.is_empty():
				missing.append(name)
			for node: Node in at:
				if node.has_node(child_name):
					continue
				var scene := load(str(row["parts"][name])) as PackedScene
				if scene == null:
					push_warning("[ArcadeDressing] %s: parts.%s did not load" % [dress_id, name])
					break
				var inst := scene.instantiate()
				inst.name = child_name
				node.add_child(inst)
				added += 1
		print("[ArcadeDressing] %s on %s (%s form): %d part(s) painted, %d scene(s) added%s" % [dress_id,
			variant if variant != "" else "a mod cabinet", shape, painted, added,
			"" if missing.is_empty() else "; this form has no " + ", ".join(missing)])


## Put a part's paint on it the way the builder did: over the instance when it was painted there (the
## sides, the stick balls), else on each surface, leaving the mesh's own material, which a baked scene shares.
static func _paint(mi: MeshInstance3D, material: Material) -> void:
	if mi.material_override != null:
		mi.material_override = material
		return
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		mi.set_surface_override_material(i, material)


static func _parts_by_name(root: Node) -> Dictionary:
	var out := {}
	for n in root.find_children("*", "", true, false):
		# Never into a dressing's own scene: its parts are the mod's, not the builder's.
		if str(n.name).begins_with(PART_PREFIX) or _under_dress(n, root):
			continue
		var key := str(n.name)
		if not out.has(key):
			out[key] = []
		(out[key] as Array).append(n)
	return out


static func _under_dress(n: Node, root: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != root:
		if str(p.name).begins_with(PART_PREFIX):
			return true
		p = p.get_parent()
	return false
