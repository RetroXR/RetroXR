## StandCatalog — the console stands: things a console is MOUNTED in, which
## decide how it stands (a PlayStation 2 on its side, a Wii upright in its cradle).
##
## A stand is the inverse of the 32X's Model 2 spacer. The spacer is an accessory
## the UNIT holds; a stand is its own object, and the CONSOLE is what it holds,
## in a StandMount snap zone, at a pose the stand's row decides. Nothing about a
## console has to know which stands exist: a console grows one StandFoot per face
## some stand rests it on (StandFoot.build_for), and a stand takes it by that foot.
## See docs/dev/console-stands.md.
##
## ── A row ───────────────────────────────────────────────────────────────────
##   label     what the spawn card calls it.
##   fits      the systemids and/or SystemModelRegistry model ids it takes. A
##             model id is narrower and is how a stand is kept off a model that
##             brings its own (the Virtual Boy primitive authors its bipod).
##   face      which face of the console's MEASURED box (RetroSystem.body_aabb)
##             rests in the stand: bottom, top, left, right, back or front. The
##             console's front stays its front for the four side faces; for back
##             and front its top faces the player. Measured, not authored, so a
##             stand fits a console's stand-in and its detailed shell alike.
##   seat      where the middle of that face goes, in the stand's frame (y up,
##             front +Z), in metres.
##   seat_rotation_deg  (optional) a turn of the seat about the stand's own
##             axes, Euler XYZ degrees: a Virtual Boy's tilt, a rack's lean.
##   parts     the stand's collision, and its look when there is no `scene`: a
##             list of {"box": Vector3 size} or {"cylinder": [radius, height]},
##             each with a "position". Required: an authored model is only the
##             look, so a stand that loses its GLB still stands and still holds.
##   scene     (optional) an authored model scene, in the stand's frame. Empty for
##             a primitive stand-in.
##   color     (optional) the primitive's plastic.
##   mass      (optional) kg.
##
## The shipped rows are PRIMITIVE STAND-INS: neither stand's dimensions are
## published, so their sizes are estimates around the real consoles' (Wii
## 157 x 44 x 215.4 mm, a fat PS2 301 x 78 x 178 mm). Replace them with the
## measured models when RetroXR-models has them, keeping the ids: a save names a
## stand by its id.
class_name StandCatalog
extends RefCounted

## The six faces a stand can rest a console on.
const FACES: Array[String] = ["bottom", "top", "left", "right", "back", "front"]

## The prefix of the group a StandMount for a face joins; StandFoot for that face
## requires it, so only a stand meant to rest a console on that face takes it.
const ZONE_GROUP_PREFIX := "console_stand_mount_"

## Shipped stands, by id. The id is persisted (a save's "stand_id"): never rename.
const _ROWS := {
	# Nintendo's RVL-017 cradle with the round RVL-019 plate clipped under it. The
	# Wii in the room LIES flat (wii_primitive.tscn is authored upright and its
	# root turns it onto its side, the authored bottom becoming the console's +X),
	# so the cradle stands it back up on that face: its RIGHT, 44 mm across.
	"wii_stand": {
		"label": "Console Stand (RVL-017)",
		"fits": ["wii"],
		"face": "right",
		"seat": Vector3(0.0, 0.010, 0.0),
		"parts": [
			# The clear plate: 130 mm across, an estimate.
			{"cylinder": [0.065, 0.004], "position": Vector3(0.0, 0.002, 0.0)},
			# The trough's floor and its two walls, 0.5 mm clear of a 44 mm Wii.
			{"box": Vector3(0.056, 0.006, 0.170), "position": Vector3(0.0, 0.007, 0.0)},
			{"box": Vector3(0.006, 0.020, 0.170), "position": Vector3(-0.0255, 0.020, 0.0)},
			{"box": Vector3(0.006, 0.020, 0.170), "position": Vector3(0.0255, 0.020, 0.0)},
		],
		"color": Color(0.86, 0.87, 0.88),
		"mass": 0.15,
	},
	# Sony's SCPH-10040 for the original ("fat") PlayStation 2: it screws to the
	# console's underside with one coin-slot screw and stands it on its LEFT side,
	# so the power and reset keys are on top and the pad ports bottom right. The
	# screw is not modelled; seated is held.
	"ps2_vertical_stand": {
		"label": "Vertical Stand (SCPH-10040)",
		"fits": ["ps2"],
		"face": "left",
		"seat": Vector3(0.0, 0.008, 0.0),
		# Drawn for a real PS2's 78 mm. Until it has a model, a PS2 is the generic
		# 300 x 100 x 250 mm box, which the arm sits inside.
		"parts": [
			# The foot, wider than the console is thick so it does not tip.
			{"box": Vector3(0.110, 0.008, 0.180), "position": Vector3(0.0, 0.004, 0.0)},
			# The arm up the console's underside -- which, on its left side, faces
			# +X -- where the screw goes in. The console is 78 mm thick.
			{"box": Vector3(0.006, 0.060, 0.120), "position": Vector3(0.042, 0.038, 0.0)},
		],
		"color": Color(0.16, 0.17, 0.19),
		"mass": 0.14,
	},
}

## Stands mods add, by id -> {row: Dictionary, owner: String}. Layered over the
## shipped rows; a mod cannot take one of their ids (it overrides one instead).
static var _mod_rows: Dictionary = {}

## A mod's changes to a SHIPPED stand, by id -> {row: Dictionary (only the fields
## it changes), owner: String}: how a model pack replaces a primitive stand-in
## with the real thing and keeps the id every save names. Merged over the shipped
## row; withdrawn with the mod, which brings the primitive back.
static var _overrides: Dictionary = {}


## Every stand id, shipped first.
static func ids() -> Array:
	var out: Array = _ROWS.keys()
	out.append_array(_mod_rows.keys())
	return out


static func has(id: String) -> bool:
	return _ROWS.has(id) or _mod_rows.has(id)


## The row for `id`, or {} for a stand nothing defines (a mod since removed).
static func row(id: String) -> Dictionary:
	if _ROWS.has(id):
		if _overrides.has(id):
			return (_ROWS[id] as Dictionary).merged((_overrides[id] as Dictionary)["row"], true)
		return _ROWS[id]
	if _mod_rows.has(id):
		return (_mod_rows[id] as Dictionary)["row"]
	return {}


static func label_of(id: String) -> String:
	return str(row(id).get("label", "Console Stand"))


static func face_of(id: String) -> String:
	return str(row(id).get("face", "bottom"))


## The StandMount's pose in the stand's frame: the seat, turned by the row.
static func seat_transform(id: String) -> Transform3D:
	var r := row(id)
	var rot: Vector3 = r.get("seat_rotation_deg", Vector3.ZERO)
	var b := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	return Transform3D(b, r.get("seat", Vector3.ZERO))


## Whether stand `id` takes a console of `systemid` wearing model `model_id`
## (already resolved: "" is not the platform default here).
static func fits(id: String, systemid: String, model_id: String) -> bool:
	var takes: Array = row(id).get("fits", [])
	return takes.has(systemid) or (not model_id.is_empty() and takes.has(model_id))


## Every stand that takes such a console.
static func stands_for(systemid: String, model_id: String) -> Array:
	return ids().filter(func(id: String) -> bool: return fits(id, systemid, model_id))


## Every stand offered on `systemid`'s spawn card: those fitting the platform or
## any model it has.
static func stands_for_card(systemid: String) -> Array:
	var models: Array = []
	for r: Dictionary in SystemModelRegistry.rows_for(systemid):
		models.append(str(r.get("id", "")))
	return ids().filter(func(id: String) -> bool:
		var takes: Array = row(id).get("fits", [])
		return takes.has(systemid) or models.any(func(m: String) -> bool: return takes.has(m)))


## The faces the stands that take such a console rest it on, each once.
static func faces_for(systemid: String, model_id: String) -> Array:
	var out: Array = []
	for id: String in stands_for(systemid, model_id):
		var face := face_of(id)
		if not out.has(face):
			out.append(face)
	return out


static func zone_group(face: String) -> String:
	return ZONE_GROUP_PREFIX + face


## The StandFoot for `face` of a box, in the console's frame: its origin the
## middle of that face, its +Y pointing INTO the console (the face's outward
## normal reversed). A zone composes it inverted, so the face lies on the seat
## with the zone's up through the console.
##
## Written as columns (x, y, z); each is right-handed (x = y cross z).
static func foot_transform(face: String, box: AABB) -> Transform3D:
	var c := box.get_center()
	var lo := box.position
	var hi := box.end
	match face:
		"top":
			return Transform3D(Basis(Vector3.LEFT, Vector3.DOWN, Vector3.BACK), Vector3(c.x, hi.y, c.z))
		"left":
			return Transform3D(Basis(Vector3.DOWN, Vector3.RIGHT, Vector3.BACK), Vector3(lo.x, c.y, c.z))
		"right":
			return Transform3D(Basis(Vector3.UP, Vector3.LEFT, Vector3.BACK), Vector3(hi.x, c.y, c.z))
		"back":
			return Transform3D(Basis(Vector3.LEFT, Vector3.BACK, Vector3.UP), Vector3(c.x, c.y, lo.z))
		"front":
			return Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3(c.x, c.y, hi.z))
		_:
			return Transform3D(Basis.IDENTITY, Vector3(c.x, lo.y, c.z))


# ── Mods ─────────────────────────────────────────────────────────────────────

## Add a stand. "" on success, else why not.
static func register_mod_stand(id: String, r: Dictionary, owner_id: String) -> String:
	if id.is_empty():
		return "no stand id"
	if _ROWS.has(id):
		return "'%s' is a shipped stand (override_console_stand changes one)" % id
	if _mod_rows.has(id):
		return "'%s' is already registered by mod '%s'" % [id, _mod_rows[id]["owner"]]
	var err := _row_error(id, r)
	if not err.is_empty():
		return err
	_mod_rows[id] = {"row": r.duplicate(true), "owner": owner_id}
	return ""


## Change a SHIPPED stand in place: `changes` is merged over its row, so a model
## pack sends its `scene` and whatever it measured differently (`seat`, `parts`)
## and nothing else. "" on success, else why not.
static func override_stand(id: String, changes: Dictionary, owner_id: String) -> String:
	if not _ROWS.has(id):
		return "'%s' is not a shipped stand" % id
	if changes.is_empty():
		return "no changes given for '%s'" % id
	if _overrides.has(id):
		return "'%s' is already overridden by mod '%s'" % [id, _overrides[id]["owner"]]
	var err := _row_error(id, (_ROWS[id] as Dictionary).merged(changes, true))
	if not err.is_empty():
		return err
	_overrides[id] = {"row": changes.duplicate(true), "owner": owner_id}
	return ""


## Why a whole row cannot be a stand, or "".
static func _row_error(id: String, r: Dictionary) -> String:
	if (r.get("fits", []) as Array).is_empty():
		return "stand '%s' fits nothing (no `fits`)" % id
	if not FACES.has(str(r.get("face", "bottom"))):
		return "stand '%s' has an unknown face '%s'" % [id, r.get("face")]
	if (r.get("parts", []) as Array).is_empty():
		return "stand '%s' has no `parts` to stand on" % id
	var scene := str(r.get("scene", ""))
	if not scene.is_empty() and not ResourceLoader.exists(scene):
		return "scene does not exist: %s" % scene
	return ""


static func drop_mod(owner_id: String) -> void:
	for id: String in _mod_rows.keys():
		if _mod_rows[id]["owner"] == owner_id:
			_mod_rows.erase(id)
	for id: String in _overrides.keys():
		if _overrides[id]["owner"] == owner_id:
			_overrides.erase(id)
