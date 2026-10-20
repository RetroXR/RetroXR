## Pointer-fit self-tests — a plug's and a memory card's pointer target is what
## they draw, headless, with no core, no ROM and no headset.
##
##     "$godot" --headless --path RetroXR res://Tests/pointer_fit_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/pointer_fit_tests.tscn -- --only=resolver
##
## Exits 0 when everything passes, 1 otherwise, so it can gate a commit.
##
## Plugs and cards carried pointer targets padded well past their shells (a 110 mm
## sphere round a 14 mm phono plug), so the desktop laser stopped in the air beside
## one and took it instead of what was aimed at. PointerFit fits them to what is
## drawn, and keeps doing it as models change at run time. The cases:
##
##   scene/    every plug and card the game ships: the target is what it shows,
##             and nothing of its body stands proud of that either;
##   swap/     a pad's plug handed a connector (set_plug_mesh), a real pad's plug,
##             and back to the generic molding;
##   dress/    a mod's way of dressing a plug or a card (a shell put on, the
##             stand-in hidden, sometimes a frame late), and a body box a mod sets
##             itself, which is left alone;
##   resolver/ InteractionResolver.resolve_desktop aimed 5 and 10 mm off what is
##             drawn does not take the thing, aimed at it does, and the padded
##             target it used to have would have taken it (the control);
##   seated/   a Controller Pak in a pad: its tongue is inside the pad, so a ray
##             at the pad over it is the pad's, and one at the pak is the pak's.
extends Node

## How many cases this file contains, NOT counting the guard below — it is
## checked before it has recorded itself. A case that never ran is not one that
## passed: bump this when adding cases.
const EXPECTED_CASES := 322

## Close enough to call two boxes the same: a tenth of a millimeter.
const TOLERANCE := 0.0001

## The pointer is aimed this far off what is drawn, and must not take it.
const BESIDE: Array[float] = [0.005, 0.010]

const CONTROLLER_CABLE := "res://Scenes/Objects/cables/controller_cable.tscn"
const PS1_PLUG := "res://Scenes/Objects/controllers/playstation/ps1_plug.res"
const KEYBOARD_PLUG := "res://Scenes/Objects/cables/ps2_plug_keyboard.res"
const PS1_PAD := "res://Scenes/Objects/controllers/playstation/ps1_controller.tscn"
const N64_PAD := "res://Scenes/Objects/controllers/n64/n64_controller.tscn"
const CONTROLLER_PAK := "res://Scenes/Objects/controllers/n64/controller_pak.tscn"
const PS2_CARD := "res://Scenes/Objects/media/ps2_memory_card.tscn"
const VMU := "res://Scenes/Objects/controllers/dreamcast/vmu_card.tscn"
const N64_AV := "res://Scenes/Objects/system_models/nintendo_64/n64_av_cable.tscn"

## Every scene that ships a plug or a card the pointer can take.
const SCENES: Array[String] = [
	"res://Scenes/Objects/cables/cable.tscn",
	"res://Scenes/Objects/cables/composite_cable.tscn",
	"res://Scenes/Objects/cables/controller_cable.tscn",
	"res://Scenes/Objects/cables/comlynx_cable.tscn",
	"res://Scenes/Objects/cables/gb_link_cable.tscn",
	"res://Scenes/Objects/cables/gc_gba_cable.tscn",
	"res://Scenes/Objects/cables/gg_link_cable.tscn",
	"res://Scenes/Objects/cables/ilink_cable.tscn",
	"res://Scenes/Objects/cables/jag_link_cable.tscn",
	"res://Scenes/Objects/cables/link_cable.tscn",
	"res://Scenes/Objects/cables/mono_composite_cable.tscn",
	"res://Scenes/Objects/cables/nema_1_15_polarized_to_c7_polarized_cord.tscn",
	"res://Scenes/Objects/cables/nema_1_15_to_c7_cord.tscn",
	"res://Scenes/Objects/cables/ngp_link_cable.tscn",
	"res://Scenes/Objects/cables/power_cord.tscn",
	"res://Scenes/Objects/cables/ps2_av_cable.tscn",
	"res://Scenes/Objects/cables/psx_link_cable.tscn",
	"res://Scenes/Objects/cables/saturn_link_cable.tscn",
	"res://Scenes/Objects/cables/speaker_cable.tscn",
	"res://Scenes/Objects/cables/trs_cable.tscn",
	"res://Scenes/Objects/cables/vb_link_cable.tscn",
	"res://Scenes/Objects/cables/vga_cable.tscn",
	"res://Scenes/Objects/cables/ws_link_cable.tscn",
	"res://Scenes/Objects/controllers/gamecube/gc_microphone_cable.tscn",
	"res://Scenes/Objects/controllers/n64/n64_vru_cable.tscn",
	"res://Scenes/Objects/controllers/wii/nunchuk_cable.tscn",
	"res://Scenes/Objects/system_models/dreamcast/dc_av_cable.tscn",
	"res://Scenes/Objects/system_models/genesis/genesis_av_cable.tscn",
	"res://Scenes/Objects/system_models/nintendo_64/n64_av_cable.tscn",
	"res://Scenes/Objects/system_models/wii/sensor_bar_cable.tscn",
	"res://Scenes/Objects/system_models/wii/wii_av_cable.tscn",
	"res://Scenes/Objects/media/memory_card.tscn",
	"res://Scenes/Objects/media/gc_memory_card.tscn",
	"res://Scenes/Objects/media/ps2_memory_card.tscn",
	"res://Scenes/Objects/controllers/dreamcast/vmu_card.tscn",
	"res://Scenes/Objects/controllers/xbox/xbox_mu.tscn",
	"res://Scenes/Objects/controllers/n64/controller_pak.tscn",
	"res://Scenes/Objects/controllers/n64/rumble_pak.tscn",
	"res://Scenes/Objects/controllers/n64/transfer_pak.tscn",
]

## The objects the resolver is aimed past: [scene, path to the pickable in it].
const AIMED_AT: Array = [
	["res://Scenes/Objects/cables/cable.tscn", "CablePlug"],
	["res://Scenes/Objects/cables/composite_cable.tscn", "PlugA1"],
	["res://Scenes/Objects/cables/controller_cable.tscn", "ControllerPlug"],
	["res://Scenes/Objects/cables/link_cable.tscn", "PlugA0"],
	["res://Scenes/Objects/cables/power_cord.tscn", "WallPlug"],
	["res://Scenes/Objects/cables/trs_cable.tscn", "PlugA0"],
	["res://Scenes/Objects/system_models/nintendo_64/n64_av_cable.tscn", "PlugA0"],
	["res://Scenes/Objects/media/memory_card.tscn", "."],
	["res://Scenes/Objects/media/gc_memory_card.tscn", "."],
	["res://Scenes/Objects/controllers/dreamcast/vmu_card.tscn", "."],
	["res://Scenes/Objects/controllers/xbox/xbox_mu.tscn", "."],
	["res://Scenes/Objects/controllers/n64/controller_pak.tscn", "."],
]

var _pass := 0
var _fail := 0
var _only := ""
## Where the next object is put: far enough from the last that no ray meets two.
var _spot := 0
var _grabber: Node3D = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--only="):
			_only = str(a).substr("--only=".length())
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[fit] TIMEOUT")
		get_tree().quit(1))

	_grabber = Node3D.new()
	add_child(_grabber)

	_ok(PointerFit.QUERY_MASK == InteractionResolver.QUERY_MASK,
		"mask/the fit trims what the desktop ray stops on, and only that")
	if _want("scene"):
		await _test_scenes()
	if _want("swap"):
		await _test_swap()
		await _test_pad_plug()
	if _want("dress"):
		await _test_dressed_plug()
		await _test_late_plug_model()
		await _test_dressed_card()
		await _test_runtime_body_is_kept()
	if _want("resolver"):
		await _test_resolver()
		await _test_resolver_dressed()
	if _want("seated"):
		await _test_seated_pak()

	if _only.is_empty():
		_ok(_pass + _fail == EXPECTED_CASES, "suite/every case ran",
			"%d ran, %d expected" % [_pass + _fail, EXPECTED_CASES])
	print("[fit] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _want(group: String) -> bool:
	return _only.is_empty() or group.begins_with(_only) or _only.begins_with(group)


func _ok(cond: bool, test_name: String, detail := "") -> void:
	if cond:
		_pass += 1
		print("[fit] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[fit] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


func _settle(frames := 3) -> void:
	for i in frames:
		await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func _mm(box: AABB) -> String:
	return "%s .. %s mm" % [str(box.position * 1000.0), str(box.end * 1000.0)]


## A scene in the room, at a spot of its own, every pickable in it frozen where
## it was put. The caller frees it.
func _place(path: String) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	_spot += 1
	node.position = Vector3(float(_spot) * 3.0, 1.5, 0.0)
	_freeze(node)
	add_child(node)
	return node


func _freeze(root: Node) -> void:
	for n: Node in [root] + root.find_children("*", "RigidBody3D", true, false):
		var body := n as RigidBody3D
		if body != null:
			body.freeze = true


## What `object` shows, in its own frame: every mesh visible in the tree under it,
## save one riding on it (another pickable, a socket's) or floating over it (a
## top-level hint). Read off global transforms, not the way PointerFit walks them.
func _shown(object: Node3D) -> AABB:
	var inv := object.global_transform.affine_inverse()
	var acc := AABB()
	var first := true
	for n: Node in object.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or _riding(mi, object):
			continue
		var ab: AABB = (inv * mi.global_transform) * mi.get_aabb()
		acc = ab if first else acc.merge(ab)
		first = false
	return acc


func _riding(node: Node, object: Node) -> bool:
	var n := node
	while n != null and n != object:
		if n is XRToolsPickable or n is XRToolsSnapZone:
			return true
		if n is Node3D and (n as Node3D).top_level:
			return true
		n = n.get_parent()
	return false


## The pointer target's box in `object`'s frame, or an empty AABB when it is not one.
func _target(object: Node3D) -> AABB:
	var col := object.get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D
	if col == null or not col.shape is BoxShape3D:
		return AABB()
	var size := (col.shape as BoxShape3D).size
	return (object.global_transform.affine_inverse() * col.global_transform) * AABB(-size * 0.5, size)


## The body's own boxes on a layer the desktop ray stops on, in `object`'s frame.
func _bodies(object: CollisionObject3D) -> Array[AABB]:
	var out: Array[AABB] = []
	if (object.collision_layer & InteractionResolver.QUERY_MASK) == 0:
		return out
	for child: Node in object.get_children():
		var col := child as CollisionShape3D
		if col == null or col.disabled or not col.shape is BoxShape3D:
			continue
		var size := (col.shape as BoxShape3D).size
		out.append(col.transform * AABB(-size * 0.5, size))
	return out


func _same(a: AABB, b: AABB) -> bool:
	return a.position.distance_to(b.position) < TOLERANCE and a.end.distance_to(b.end) < TOLERANCE


## Every plug and card class PointerFit is wired into.
func _fitted(node: Node) -> bool:
	return node is CablePlug or node is ControllerPlug or node is RcaPlug \
		or node is GcMicrophonePlug or node is N64VruMicPlug or node is MemoryCard \
		or node is VmuCard or node is XboxMuCard or node is N64Pak


## The target and the bodies of `object` hold to what it shows.
func _check_fit(object: CollisionObject3D, label: String) -> void:
	var shown := _shown(object)
	var aim := _target(object)
	_ok(shown.has_volume() and _same(aim, shown), "%s: the pointer target is what it shows" % label,
		"target %s, shown %s" % [_mm(aim), _mm(shown)])
	var proud := []
	for body: AABB in _bodies(object):
		if not shown.grow(PointerFit.BODY_SLACK + TOLERANCE).encloses(body):
			proud.append(_mm(body))
	_ok(proud.is_empty(), "%s: and none of its body stands proud of it" % label,
		"shown %s, bodies %s" % [_mm(shown), str(proud)])


# ── scene/ ───────────────────────────────────────────────────────────────────

func _test_scenes() -> void:
	for path: String in SCENES:
		var root := _place(path)
		await _settle()
		var objects: Array[Node] = []
		for n: Node in [root] + root.find_children("*", "XRToolsPickable", true, false):
			if _fitted(n):
				objects.append(n)
		_ok(not objects.is_empty(), "scene/%s has a plug or a card" % path.get_file())
		for n: Node in objects:
			_check_fit(n as CollisionObject3D, "scene/%s %s" % [path.get_file(), root.get_path_to(n)])
		root.queue_free()
		await get_tree().process_frame


# ── swap/ ────────────────────────────────────────────────────────────────────

func _test_swap() -> void:
	var cable := _place(CONTROLLER_CABLE)
	await _settle()
	var plug := cable.get_node("ControllerPlug") as ControllerPlug
	var generic := _shown(plug)
	var body := plug.get_node("CollisionShape3D") as CollisionShape3D
	var authored := body.shape
	var authored_size := (authored as BoxShape3D).size
	var authored_box := AABB(body.position - authored_size * 0.5, authored_size)
	var was_cut := false
	_check_fit(plug, "swap/the generic molding")

	plug.set_plug_mesh(PS1_PLUG)
	await _settle()
	var worn := plug.get_node_or_null("PlugModel") as MeshInstance3D
	_ok(worn != null and not (plug.get_node("PlugTip") as Node3D).visible,
		"swap/the PlayStation's connector is on, the molding hidden")
	var ps1 := _shown(plug)
	_ok(not _same(ps1, generic), "swap/and it is not the molding's size",
		"%s against %s" % [_mm(ps1), _mm(generic)])
	_check_fit(plug, "swap/the PlayStation's connector")
	var proud := not ps1.grow(PointerFit.BODY_SLACK).encloses(authored_box)
	_ok(proud == (body.shape != authored),
		"swap/the molding's body is cut back to the connector where it stood proud of it, and only there")
	was_cut = was_cut or body.shape != authored

	plug.set_plug_mesh(KEYBOARD_PLUG)
	await _settle()
	var ps2 := _shown(plug)
	_ok(not _same(ps2, ps1) and not _same(ps2, generic), "swap/a keyboard's PS/2 plug is a third size",
		_mm(ps2))
	_check_fit(plug, "swap/the keyboard's PS/2 plug")
	proud = not ps2.grow(PointerFit.BODY_SLACK).encloses(authored_box)
	_ok(proud == (body.shape != authored),
		"swap/and to the PS/2 plug, measured from the molding's box and not the last cut")
	was_cut = was_cut or body.shape != authored
	_ok(was_cut, "swap/one connector or the other did have the body cut back")

	plug.set_plug_mesh("")
	await _settle()
	_ok(plug.get_node_or_null("PlugModel") == null and _same(_shown(plug), generic),
		"swap/back to the molding")
	_check_fit(plug, "swap/the molding again")
	_ok(body.shape == authored, "swap/and its body is the scene's own box again",
		str((body.shape as BoxShape3D).size if body.shape is BoxShape3D else body.shape))
	cable.queue_free()
	await get_tree().process_frame


## The way the room does it: a pad puts its cord in the room and its plug wears
## the connector the pad names (plug_mesh_path).
func _test_pad_plug() -> void:
	var pad := _place(PS1_PAD)
	await _settle(8)
	var plug: ControllerPlug = null
	if pad.has_method("get_plug"):
		plug = pad.call("get_plug") as ControllerPlug
	_ok(plug != null and plug.get_node_or_null("PlugModel") != null,
		"swap/a PlayStation pad's plug wears the pad's connector")
	if plug != null:
		plug.freeze = true
		await _settle()
		_check_fit(plug, "swap/the pad's plug")
		var cable := plug.get_parent()
		if cable != null:
			cable.queue_free()
	pad.queue_free()
	await get_tree().process_frame


# ── dress/ ───────────────────────────────────────────────────────────────────

## A box of `size` centered at `at`, as a mod's shell: a Node3D holding a mesh.
func _shell(shell_name: String, size: Vector3, at: Vector3) -> Node3D:
	var shell := Node3D.new()
	shell.name = shell_name
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = at
	shell.add_child(mi)
	return shell


## The xenu.n64av way: the stand-in's meshes hidden, a "Shell" hung on the plug.
## Done to a plug already in the room, as a hook on a plug that arrives later is.
func _test_dressed_plug() -> void:
	var lead := _place(N64_AV)
	await _settle()
	var plug := lead.get_node("PlugA0") as RcaPlug
	var stand_in := _shown(plug)
	for child: Node in plug.get_children():
		if child is MeshInstance3D:
			(child as Node3D).visible = false
	var shell_box := AABB(Vector3(-0.005, -0.002, -0.025), Vector3(0.010, 0.006, 0.030))
	plug.add_child(_shell("Shell", shell_box.size, shell_box.get_center()))
	await _settle()
	_ok(_same(_shown(plug), shell_box), "dress/the plug shows the shell and only the shell",
		_mm(_shown(plug)))
	_ok(not _same(_target(plug), stand_in), "dress/the target has left the stand-in")
	_check_fit(plug, "dress/the Multi Out plug in a mod's shell")
	lead.queue_free()
	await get_tree().process_frame


## The xenu.n64pad way: the plug's model put on a few frames after the cord is in
## the room, named as the game names its own.
func _test_late_plug_model() -> void:
	var cable := _place(CONTROLLER_CABLE)
	await _settle()
	var plug := cable.get_node("ControllerPlug") as ControllerPlug
	await get_tree().process_frame
	for generic: String in ["PlugTip", "StrainRelief"]:
		(plug.get_node(generic) as Node3D).visible = false
	var model_box := AABB(Vector3(-0.007, -0.003, -0.03), Vector3(0.014, 0.006, 0.038))
	plug.add_child(_shell("PlugModel", model_box.size, model_box.get_center()))
	await _settle()
	_ok(_same(_target(plug), model_box), "dress/a model put on late is what the plug is aimed by",
		_mm(_target(plug)))
	_check_fit(plug, "dress/the late model")
	# Taken off again, the molding is back and so is its target.
	plug.get_node("PlugModel").free()
	for generic: String in ["PlugTip", "StrainRelief"]:
		(plug.get_node(generic) as Node3D).visible = true
	await _settle()
	_check_fit(plug, "dress/the molding after the model is taken off")
	cable.queue_free()
	await get_tree().process_frame


## The xenu.ps2card way: the shell on, then the stand-in hidden.
func _test_dressed_card() -> void:
	var card := _place(PS2_CARD) as MemoryCard
	await _settle()
	var stand_in := _shown(card)
	var shell_box := AABB(Vector3(-0.015, -0.003, -0.02), Vector3(0.03, 0.006, 0.04))
	card.add_child(_shell("Shell", shell_box.size, shell_box.get_center()))
	for part: String in ["CardMesh", "PlateMesh", "StripeMesh"]:
		(card.get_node(part) as Node3D).visible = false
	await _settle()
	_ok(_same(_target(card), shell_box), "dress/a PlayStation 2 card is aimed by its shell",
		_mm(_target(card)))
	_ok(not _same(_target(card), stand_in), "dress/not by the stand-in it hid")
	_check_fit(card, "dress/the dressed card")
	card.queue_free()
	await get_tree().process_frame


## A body box set at run time was fitted by whoever set it: the VMU mod sizes the
## card's body for the cap that rides on its end. It is left alone.
func _test_runtime_body_is_kept() -> void:
	var vmu := (load(VMU) as PackedScene).instantiate() as Node3D
	var body := vmu.get_node("CollisionShape3D") as CollisionShape3D
	var theirs := BoxShape3D.new()
	theirs.size = Vector3(0.048, 0.1, 0.02)
	body.shape = theirs
	_spot += 1
	vmu.position = Vector3(float(_spot) * 3.0, 1.5, 0.0)
	_freeze(vmu)
	add_child(vmu)
	await _settle()
	_ok(body.shape == theirs and theirs.size == Vector3(0.048, 0.1, 0.02),
		"dress/a body box a mod set is its own and is left as it set it")
	_ok(_same(_target(vmu), _shown(vmu)), "dress/the pointer target is still what the card shows")
	vmu.queue_free()
	await get_tree().process_frame


# ── resolver/ ────────────────────────────────────────────────────────────────

## What the desktop pointer resolves along a ray from `from` to `to`.
func _resolve(from: Vector3, to: Vector3) -> InteractionTarget:
	return InteractionResolver.resolve_desktop(get_viewport().world_3d.direct_space_state,
		from, to, _grabber)


func _takes(t: InteractionTarget, object: Node3D) -> bool:
	return t != null and (t.action_node == object or t.highlight_node == object)


## Aim at `object` and just past it, from above (down -Y) and from the side
## (along -X). Its frame may be turned, but only by quarter turns.
func _aim_round(object: Node3D, label: String) -> void:
	var shown := object.global_transform * _shown(object)
	var lo := shown.position
	var hi := shown.end
	var mid := shown.get_center()
	var t := _resolve(Vector3(mid.x, hi.y + 0.4, mid.z), Vector3(mid.x, lo.y - 0.1, mid.z))
	_ok(_takes(t, object), "%s: aimed at, it is taken" % label,
		"got %s" % (str(t.action_node.name) if t.action_node != null else String(t.kind)))
	for d: float in BESIDE:
		var mm := int(round(d * 1000.0))
		var past_x := _resolve(Vector3(hi.x + d, hi.y + 0.4, mid.z), Vector3(hi.x + d, lo.y - 0.1, mid.z))
		_ok(not _takes(past_x, object), "%s: %d mm beside it, from above, it is not" % [label, mm])
		var past_y := _resolve(Vector3(hi.x + 0.4, hi.y + d, mid.z), Vector3(lo.x - 0.1, hi.y + d, mid.z))
		_ok(not _takes(past_y, object), "%s: %d mm over it, from the side, it is not" % [label, mm])


func _test_resolver() -> void:
	for entry: Array in AIMED_AT:
		var root := _place(str(entry[0]))
		var object := root.get_node(NodePath(str(entry[1]))) as CollisionObject3D
		# Clear of the rest of its lead: the plugs of one sit a few mm apart.
		if object != root:
			object.position += Vector3(0.0, 0.6, 0.0)
		await _settle()
		var label := "resolver/%s %s" % [str(entry[0]).get_file(), str(entry[1])]
		_aim_round(object, label)
		await _control(object, str(entry[0]), str(entry[1]), label)
		root.queue_free()
		await get_tree().process_frame


## The check can fail: the scene's own padded target, put back, takes a ray that
## the fitted one lets by.
func _control(object: CollisionObject3D, scene: String, path: String, label: String) -> void:
	var fresh := (load(scene) as PackedScene).instantiate()
	var authored := fresh.get_node(NodePath(path)).get_node("PointerArea/CollisionShape3D") as CollisionShape3D
	var col := object.get_node("PointerArea/CollisionShape3D") as CollisionShape3D
	var padded := object.global_transform * ((col.get_parent() as Node3D).transform \
		* authored.transform * _shape_box(authored.shape))
	var shown := object.global_transform * _shown(object)
	if padded.end.x < shown.end.x + 0.002:
		fresh.free()
		return
	var fitted_shape := col.shape
	var fitted_at := col.transform
	col.shape = authored.shape
	col.transform = authored.transform
	await _settle(1)
	var x := (shown.end.x + padded.end.x) * 0.5
	var mid := shown.get_center()
	var t := _resolve(Vector3(x, shown.end.y + 0.4, mid.z), Vector3(x, shown.position.y - 0.1, mid.z))
	_ok(_takes(t, object), "%s: the padded target it had would have taken a ray %.1f mm beside it"
		% [label, (x - shown.end.x) * 1000.0])
	col.shape = fitted_shape
	col.transform = fitted_at
	fresh.free()
	await _settle(1)


func _shape_box(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		return AABB(-Vector3.ONE * r, Vector3.ONE * 2.0 * r)
	return AABB()


## A plug dressed smaller than the body its scene gave it: the body is cut back, so
## a ray beside the shell passes where the stand-in's body would have stopped it.
func _test_resolver_dressed() -> void:
	var cable := _place(CONTROLLER_CABLE)
	await _settle()
	var plug := cable.get_node("ControllerPlug") as ControllerPlug
	for generic: String in ["PlugTip", "StrainRelief"]:
		(plug.get_node(generic) as Node3D).visible = false
	var model_box := AABB(Vector3(-0.004, -0.003, -0.03), Vector3(0.008, 0.006, 0.04))
	plug.add_child(_shell("PlugModel", model_box.size, model_box.get_center()))
	await _settle()
	var generic_body := AABB(Vector3(-0.01, -0.01, -0.04), Vector3(0.02, 0.02, 0.06))
	_ok(generic_body.end.x > model_box.end.x + BESIDE[0] and generic_body.end.y > model_box.end.y + BESIDE[0],
		"resolver/the molding's body reaches past where the dressed plug is aimed beside")
	_aim_round(plug, "resolver/a plug dressed smaller than its molding")
	cable.queue_free()
	await get_tree().process_frame


# ── seated/ ──────────────────────────────────────────────────────────────────

## A Controller Pak seated in an N64 pad. Its tongue goes into the pad, and is
## part of what the pak draws: it is inside the pad's own box, so a ray at the pad
## right over it is the pad's, not the pak's, and the pak is still the pak's.
func _test_seated_pak() -> void:
	var pad := _place(N64_PAD)
	var pak := _place(CONTROLLER_PAK)
	await _settle(6)
	var port := pad.get_node_or_null("ExpansionPort") as XRToolsSnapZone
	_ok(port != null, "seated/the pad has its expansion port")
	if port == null:
		pad.queue_free()
		pak.queue_free()
		return
	port.pick_up_object(pak)
	await _settle(6)
	_ok(pad.call("get_pak") == pak, "seated/the pak is in the pad")
	var tongue := (pak.get_node("Tongue") as MeshInstance3D)
	var tongue_box: AABB = tongue.global_transform * tongue.get_aabb()
	var pad_top := pad.global_position.y + 0.2
	var at := tongue_box.get_center()
	var down := _resolve(Vector3(at.x, pad_top, at.z), Vector3(at.x, tongue_box.position.y - 0.001, at.z))
	_ok(_takes(down, pad) and not _takes(down, pak),
		"seated/aimed down at the pad over the pak's tongue, it is the pad",
		"got %s" % (str(down.action_node.name) if down.action_node != null else String(down.kind)))
	# From under the pak, in its own frame: up its -Y face, toward the pad.
	var shown := _shown(pak)
	var c := shown.get_center()
	var up := _resolve(pak.global_transform * Vector3(c.x, shown.position.y - 0.4, c.z),
		pak.global_transform * Vector3(c.x, shown.position.y + 0.005, c.z))
	_ok(_takes(up, pak), "seated/aimed up at the pak, it is the pak",
		"got %s" % (str(up.action_node.name) if up.action_node != null else String(up.kind)))
	_check_fit(pak, "seated/the seated pak")
	port.drop_object()
	pad.queue_free()
	pak.queue_free()
	await get_tree().process_frame
