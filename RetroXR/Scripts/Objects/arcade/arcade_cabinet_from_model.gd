## ArcadeCabinetFromModel — a cabinet a mod draws (a GLB of a real cabinet) made into a playing one.
##
## A cabinet of a mod's own runs RetroSystemModelArcadeCabinet, which finds its parts through ArcadeModules
## (docs/modding.md "Arcade cabinets"): each module finds ITS parts by name in its own subtree. A model made
## in a modelling program has no modules, and names its parts as its maker does. This node, a child of the
## cabinet's root, builds the modules from the model's parts at load, before the root collects them (a
## child is ready before its parent):
##
##   the model's part (the models repo's convention, sega/arcade/common/candy.py)   becomes
##   Stick<n>Pivot, P<n>Button<k>Pivot, Start<n>Pivot                               player n's panel: StickPivot, Btn<k>, Start
##   Screen (a mesh whose face is UV-mapped 0..1 over the glass)                    the monitor: CabinetScreen
##   CoinSlot<n>, CoinSpawn<n>, CoinDrop<n>, CoinReturn<n>, ReturnCup<n>            player n's coin door (its slot and return
##                                                                                  are buttons made here, at the markers)
##   BoardDoorPivot (the board's door, swinging about +Y, opening at negative angles) the bay's door, with a hinge to take it by
##   BoardTrayPivot (a tray sliding out along +Z by `tray_travel`)                  a drawer the bay rides on
##   BoardAnchor                                                                    the bay's BayMount: the board (an
##                                                                                  ArcadeBayUnit) clips in there, turned
##                                                                                  by `bay_roll_deg`
##   <Name>DoorPivot (another door, swinging about +Y; hinged on its left edge it      a door of its own that opens, with a
##   opens at negative angles, on its right edge at positive)                       hinge to take it by (<Name>Grab)
##   <Name>HatchPivot (a service hatch hinged along its bottom edge)                 a hatch that drops open outward, about
##                                                                                  the cabinet's X, with a hinge to take it by
##   <Lead>Aim (beside any of the leads below)                                      the way that lead's socket faces: its
##                                                                                  plug comes from there
##   PowerSwitchAnchor, PowerSwitchAim                                              the cabinet's main switch (on its AC
##                                                                                  unit): the power button goes there,
##                                                                                  pressed toward the anchor from the aim
##   GdDriveAnchor                                                                  where a NAOMI GD-ROM drive stands: a
##                                                                                  snap zone that takes one (GdDriveMount)
##   Marquee, MarqueeArt                                                            found by the cabinet as they are
##
## The parts are moved under the modules keeping where they are; the rest of the model stays as drawn. The
## model's frame is the models repo's: the origin on the floor at the middle of the FRONT face, +Y up, the
## body running back along -Z. The cabinet's is centred on its base, so the model is moved back by half its
## depth, and the cabinet's size (its collision) is taken from the model's bounds.
class_name ArcadeCabinetFromModel
extends Node3D

const SCRIPT_CONTROL := "res://Scripts/Objects/arcade/arcade_control_module.gd"
const SCRIPT_SCREEN := "res://Scripts/Objects/arcade/arcade_screen_module.gd"
const SCRIPT_COIN := "res://Scripts/Objects/arcade/arcade_coin_module.gd"
const SCRIPT_BAY := "res://Scripts/Objects/arcade/arcade_bay_module.gd"
const SCRIPT_BUTTON := "res://Scripts/Objects/widgets/vr_button.gd"
const SCRIPT_HINGE := "res://Scripts/Objects/widgets/vr_hinge.gd"
const SCRIPT_GRIP := "res://Scripts/Objects/arcade/arcade_panel_grip.gd"
const SCRIPT_DRAWER := "res://Scripts/Objects/widgets/vr_drawer.gd"

## The cabinet's model (a GLB).
@export var model: PackedScene
## The players (panels and coin doors) the model has.
@export var players: int = 2
## The buttons a player's panel has.
@export var buttons: int = 6
## The monitor's glass, width x height in metres (the screen takes its picture's shape from the core).
@export var glass_size: Vector2 = Vector2(0.50, 0.38)
## Which boards the bay takes (ArcadeProfiles bay kinds: "jamma", "naomi", "sega_jvs" ...).
@export var bay_kind: String = ArcadeProfiles.BAY_JAMMA
## How far the board's door opens (degrees).
@export var door_open_deg: float = 100.0
## How far the board's tray slides out (metres); 0: it does not.
@export var tray_travel: float = 0.0
## The board's turn in its mount about the cabinet's front axis (+Z), degrees: 0 stands it on its base; -90 stands
## it on edge with its top toward +X (the Atomiswave AWSD's PCB base). The model's BoardAnchor carries no turn.
@export var bay_roll_deg: float = 0.0
## The leads that are the cabinet's own cords, by their marker ("VgaLead", "JvsLead", "BoardPowerLead"): on a real cabinet
## the monitor's VGA cable, the I/O board's JVS cable and the supply's harness are fitted when it is built and run inside
## it, so all an operator meets is a cord hanging in the base with a plug on its free end. Each such lead's socket is at
## its marker (where the cord comes out, a grommet), hidden: the plug that seats there is hidden and fixed, and its cord
## hangs from there (NaomiHookup.seed_cords lays it, a metre long). A captive JVS lead has no stand-in I/O board.
@export var captive_leads: PackedStringArray = PackedStringArray()
## The cabinet's collision, box by box, in the model's frame (meters): when given, the whole of it, in place of the
## generic shell's boxes (which stood a slab across a low bay's tray and walls in front of its doors). A models repo
## item makes the list from its own mesh (naomi-universal's tools/collision_boxes.py).
@export var solid_boxes: Array[AABB] = []

var _model: Node3D = null


func _ready() -> void:
	if model == null:
		push_warning("[ArcadeCabinet] %s has no model to build from" % get_parent().name)
		return
	_model = model.instantiate() as Node3D
	_model.name = "Model"
	add_child(_model)
	var ab := _mesh_bounds(_model)
	# The front face's middle to the base's: back by half the depth.
	_model.position = Vector3(0.0, 0.0, -(ab.position.z + ab.size.z * 0.5))
	var root := get_parent()
	if root != null:
		root.set("cabinet_width", ab.size.x)
		root.set("cabinet_height", ab.size.y)
		# The model's own boxes, moved as the model is; or, whatever of the body is deeper than the generic shell's
		# 0.40 behind the middle, one solid box.
		var half := ab.size.z * 0.5
		if not solid_boxes.is_empty():
			var shell: Array[AABB] = []
			for bx: AABB in solid_boxes:
				shell.append(AABB(bx.position + _model.position, bx.size))
			root.set_meta(RetroSystemModelArcadeCabinet.SHELL_BOXES_META, shell)
		elif half > 0.40 + 0.01:
			var solid: Array = root.get_meta(ArcadeCabinetBuilder.SOLID_BOXES_META, [])
			solid.append(AABB(Vector3(-ab.size.x * 0.5, 0.0, -half), Vector3(ab.size.x, ab.size.y, half - 0.40)))
			root.set_meta(ArcadeCabinetBuilder.SOLID_BOXES_META, solid)
	# The main switch where the model has it: the cabinet's power button goes there (configure_buttons).
	var sw := _part("PowerSwitchAnchor")
	if root != null and sw != null:
		var aim := _part("PowerSwitchAim")
		var up := (aim.global_position - sw.global_position).normalized() if aim != null else Vector3.BACK
		var side := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.BACK
		var x := side.cross(up).normalized()
		var b := Basis(x, up, x.cross(up).normalized())
		root.set_meta(RetroSystemModelArcadeCabinet.POWER_SWITCH_META, (root as Node3D).global_transform.affine_inverse() * Transform3D(b, sw.global_position))
	# Aimed at by its own mesh (RetroSystemModelArcadeCabinet._build_pointer_shapes), not the generic shell's boxes.
	var body := _model.find_child("Body", true, false) as MeshInstance3D
	if root != null and body != null:
		root.set_meta(RetroSystemModelArcadeCabinet.POINTER_MESH_META, body)
	_build_screen(root)
	for n in range(1, players + 1):
		_build_panel(n)
		_build_coin(n)
	_build_bay()
	_build_leads()
	_build_drive_mount()
	_build_doors()


## The cabinet's ends of the board's cords, at the model's leads (NaomiHookup reads them): the monitor's VGA and the
## amplifier's phono jacks in, the I/O board's JVS socket (a USB-B), the supply's power lead and, in a JAMMA cabinet,
## the JAMMA harness. Each takes its plug along -Z.
func _build_leads() -> void:
	var rows := [["VgaLead", NaomiHookup.CAB_VGA, "res://Scripts/Objects/cables/vga_port.gd", "vga_plug", RcaPort.Direction.IN, RcaPort.Channel.VIDEO],
		["AudioLeadL", NaomiHookup.CAB_AUDIO_L, "res://Scripts/Objects/cables/rca_port.gd", Connectors.PHONO, RcaPort.Direction.IN, RcaPort.Channel.AUDIO_L],
		["AudioLeadR", NaomiHookup.CAB_AUDIO_R, "res://Scripts/Objects/cables/rca_port.gd", Connectors.PHONO, RcaPort.Direction.IN, RcaPort.Channel.AUDIO_R],
		["JvsLead", NaomiHookup.CAB_JVS, "res://Scripts/Objects/cables/port.gd", NaomiHookup.USB_B, -1, -1],
		["BoardPowerLead", NaomiHookup.CAB_POWER, "res://Scripts/Objects/cables/port.gd", NaomiHookup.NAOMI_POWER, -1, -1],
		["JammaLead", NaomiHookup.CAB_JAMMA, "res://Scripts/Objects/cables/jamma_port.gd", "jamma_plug", RcaPort.Direction.IN, -1]]
	# A JAMMA cabinet has no I/O board: a NAOMI's JVS goes to a JVS-to-JAMMA converter on the harness instead.
	var jamma := _part("JammaLead") != null
	for r: Array in rows:
		var at := _part(str(r[0]))
		if at == null or (jamma and str(r[0]) == "JvsLead"):
			continue
		var captive := captive_leads.has(str(r[0]))
		if str(r[0]) == "JvsLead" and not captive:
			at = _io_board(at)
		var port := NaomiHookup.make_port(str(r[1]), str(r[2]), str(r[3]), int(r[4]), int(r[5]))
		if port is RcaPort:
			port.set("show_jack", false)
		if captive:
			port.set_meta(NaomiHookup.CAPTIVE_META, true)
			port.has_picked_up.connect(_captive_seated.bind(port))
		# The supply's second lead, for a GD-ROM drive, beside the board's.
		if str(r[0]) == "BoardPowerLead":
			var dp := NaomiHookup.make_port(NaomiGdRom.CAB_DRIVE_POWER, "res://Scripts/Objects/cables/port.gd", NaomiHookup.NAOMI_POWER)
			add_child(dp)
			dp.global_transform = Transform3D(Basis.IDENTITY, at.global_position + Vector3(0.05, 0.0, 0.0))
		if at.name == "JvsInAnchor":
			at.add_child(port)
		else:
			add_child(port)
			port.global_transform = Transform3D(_lead_facing(str(r[0]), at.global_position), at.global_position)


## The cabinet end of one of its own cords seated: out of sight in the grommet, and fixed there (neither it nor the
## socket can be taken from). A save brings the cord back seated, and this hides it again.
func _captive_seated(what: Node3D, port: Port) -> void:
	if what == null:
		return
	for m in what.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).visible = false
	if what is XRToolsPickable:
		(what as XRToolsPickable).enabled = false
	port.enabled = false


## A lead's socket takes its plug along -Z: from the front, or, when the model has a `<lead>Aim` marker, from there.
func _lead_facing(lead: String, at: Vector3) -> Basis:
	var aim := _part(lead + "Aim")
	if aim == null or aim.global_position.is_equal_approx(at):
		return Basis.IDENTITY
	var z := (aim.global_position - at).normalized()
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	var x := up.cross(z).normalized()
	return Basis(x, z.cross(x), z)


## The model's doors besides the board's (<Name>DoorPivot): each hangs on a hinge of its own a hand takes it by, swinging
## about +Y toward the player to `door_open_deg` (the hinge on the door's left edge opens it at negative angles, on its
## right edge at positive). A VRHinge, so a save keeps how far open it is.
func _build_doors() -> void:
	var pivots: Array[Node] = _model.find_children("*DoorPivot", "Node3D", true, false)
	pivots.append_array(_model.find_children("*HatchPivot", "Node3D", true, false))
	for pivot_node in pivots:
		var door := pivot_node as Node3D
		if door.name == "BoardDoorPivot" or not is_ancestor_of(door):
			continue
		var door_name := str(door.name).trim_suffix("Pivot")
		var hatch := door_name.ends_with("Hatch")
		var m := Node3D.new()
		m.name = door_name + "Hinge"
		add_child(m)
		var mb := _mesh_bounds_in(door, self)
		# Hinged on its right edge (its middle left of the pivot): opening is +Y; on its left, -Y.
		var right_edge := mb.get_center().x < to_local(door.global_position).x
		var axis := Node3D.new()
		axis.name = "DoorAxis"
		m.add_child(axis)
		var hx := Vector3(0, 1, 0) if right_edge else Vector3(0, -1, 0)
		var axis_basis := Basis(hx, Vector3(-hx.y, 0, 0), Vector3(0, 0, 1))
		if hatch:
			# A hatch drops open about the cabinet's X, its top swinging away from the cabinet: on the back (-Z) about -X.
			var back := to_local(door.global_position).z < 0.0
			axis_basis = Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)) if back else Basis.IDENTITY
		axis.global_transform = Transform3D(global_basis * axis_basis, door.global_position)
		var turn := Node3D.new()
		turn.name = "DoorPivot"
		axis.add_child(turn)
		door.reparent(turn, true)
		var db := _mesh_bounds_in(door, turn)
		var grab := Area3D.new()
		grab.name = door_name + "Grab"
		grab.set_script(load(SCRIPT_HINGE))
		grab.collision_layer = 0
		grab.collision_mask = 0
		grab.set("engage_radius", 0.12)
		grab.set("target", turn)
		grab.set("min_deg", 0.0)
		grab.set("max_deg", door_open_deg)
		grab.set("grip_engages", true)
		grab.set("box_engages", true)
		turn.add_child(grab)
		grab.position = db.get_center()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = db.size.max(Vector3(0.03, 0.03, 0.03))
		col.shape = shape
		grab.add_child(col)


## A NAOMI GD-ROM drive's place, at the model's GdDriveAnchor (its origin on the floor under the drive's body, its
## sockets toward -X): a snap zone that takes the drive, so it stands there and rides with the cabinet. A mod zone,
## so a save records the drive in it (ScenePersistence._attachment_field).
func _build_drive_mount() -> void:
	var at := _part("GdDriveAnchor")
	if at == null:
		return
	var zone := (load("res://addons/godot-xr-tools/objects/snap_zone.tscn") as PackedScene).instantiate() as XRToolsSnapZone
	zone.name = "GdDriveMount"
	zone.snap_require = NaomiGdDrive.GROUP
	zone.grab_distance = 0.12
	zone.add_to_group(ScenePersistence.MOD_ZONE_GROUP)
	add_child(zone)
	zone.global_transform = Transform3D(at.global_basis.orthonormalized(), at.global_position)


## A JVS cabinet's I/O board (837-13551) at its JvsLead: a stand-in board (a mod dresses it, ArcadeBayShells kind
## "jvs_io_board"), placed so its USB-B (its JvsInAnchor) is where the model says the lead is. Returns that marker,
## where the cabinet's JVS socket goes.
func _io_board(lead: Node3D) -> Node3D:
	var io := Node3D.new()
	io.name = "IoBoard"
	add_child(io)
	var pcb := MeshInstance3D.new()
	pcb.name = "IoBoardPcb"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.155, 0.0016, 0.092)
	pcb.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.41, 0.24)
	pcb.material_override = mat
	io.add_child(pcb)
	pcb.position = Vector3(0, 0.0118, 0)
	var anchor := Marker3D.new()
	anchor.name = "JvsInAnchor"
	io.add_child(anchor)
	anchor.position = Vector3(-0.064, 0.018, -0.046)
	ArcadeBayShells.dress(io, "jvs_io_board", Vector3(0.155, 0.024, 0.098))
	io.global_position += lead.global_position - anchor.global_position
	return anchor


func _part(part_name: String) -> Node3D:
	return _model.find_child(part_name, true, false) as Node3D


## A module of `script`, at this node's origin (the cabinet's frame), holding the parts moved into it.
func _module(module_name: String, script: String, p: int = -1) -> Node3D:
	var m := Node3D.new()
	m.name = module_name
	m.set_script(load(script))
	if p >= 0:
		m.set("player", p)
	add_child(m)
	return m


func _move(part: Node3D, into: Node3D, new_name: String) -> Node3D:
	if part == null:
		return null
	part.reparent(into, true)
	part.name = new_name
	return part


func _build_screen(root: Node) -> void:
	var glass := _part("Screen")
	if glass == null:
		return
	var m := _module("Screen", SCRIPT_SCREEN)
	m.set("glass_size", glass_size)
	_move(glass, m, "CabinetScreen")
	if root != null:
		var gb := _mesh_bounds_in(glass, self)
		root.set("screen_front_z", gb.end.z)


func _build_panel(n: int) -> void:
	var stick := _part("Stick%dPivot" % n)
	var start := _part("Start%dPivot" % n)
	if stick == null and start == null and _part("P%dButton1Pivot" % n) == null:
		return
	var m := _module("PanelP%d" % n, SCRIPT_CONTROL, n - 1)
	var parts: Array[Node3D] = []
	if stick != null:
		parts.append(_move(stick, m, "StickPivot"))
	for k in range(1, buttons + 1):
		var cap := _part("P%dButton%dPivot" % [n, k])
		if cap != null:
			cap.set_meta(&"press_offset", Vector3(0.0, -ArcadeControlModule.CAP_PRESS * 0.5, 0.0))
			parts.append(_move(cap, m, "Btn%d" % k))
	if start != null:
		start.set_meta(&"press_offset", Vector3(0.0, -ArcadeControlModule.CAP_PRESS * 0.5, 0.0))
		parts.append(_move(start, m, "Start"))
	# The whole panel is one thing to take hold of: a box round its controls.
	var box := AABB()
	var first := true
	for p: Node3D in parts:
		var b := _mesh_bounds_in(p, m)
		if b.size == Vector3.ZERO:
			b = AABB(p.position, Vector3.ZERO)
		box = b if first else box.merge(b)
		first = false
	box = box.grow(0.03)
	var grip := Area3D.new()
	grip.name = "PanelGrip"
	grip.set_script(load(SCRIPT_GRIP))
	grip.collision_layer = 0
	grip.collision_mask = 0
	grip.set("panel_size", Vector2(box.size.x, box.size.z))
	m.add_child(grip)
	grip.position = box.get_center()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(box.size.x, maxf(box.size.y, 0.06), box.size.z)
	col.shape = shape
	grip.add_child(col)


func _button(parent: Node3D, button_name: String, at: Vector3, size: Vector3) -> Area3D:
	var b := Area3D.new()
	b.name = button_name
	b.set_script(load(SCRIPT_BUTTON))
	b.collision_layer = 0
	b.collision_mask = 0
	b.set("trigger_radius", 0.02)
	b.set("depress_depth", 0.002)
	b.set("depress_axis", Vector3(0, 0, -1))
	parent.add_child(b)
	b.global_position = at
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = Vector3(0, 0, size.z * 0.3)
	b.add_child(col)
	return b


func _build_coin(n: int) -> void:
	var slot := _part("CoinSlot%d" % n)
	if slot == null:
		return
	var m := _module("CoinP%d" % n, SCRIPT_COIN, n - 1)
	_button(m, "CoinSlot", slot.global_position, Vector3(0.05, 0.04, 0.04))
	var ret := _part("CoinReturn%d" % n)
	if ret != null:
		_button(m, "CoinReturn", ret.global_position, Vector3(0.03, 0.03, 0.03))
	_move(_part("CoinSpawn%d" % n), m, "CoinSpawn")
	_move(_part("CoinDrop%d" % n), m, "CoinDrop")
	_move(_part("ReturnCup%d" % n), m, "ReturnCup")
	slot.queue_free()
	if ret != null:
		ret.queue_free()


func _build_bay() -> void:
	var anchor := _part("BoardAnchor")
	if anchor == null:
		return
	var m := _module("Bay", SCRIPT_BAY)
	m.set("bay_kind", bay_kind)
	m.set("open_deg", door_open_deg)
	# The door: VRHinge turns its target about the target's own X; the model's door swings about +Y, opening at
	# negative angles. An axis node turned so its X is -Y carries a pivot the hinge turns, and the door hangs on it.
	var door := _part("BoardDoorPivot")
	if door != null:
		var axis := Node3D.new()
		axis.name = "DoorAxis"
		m.add_child(axis)
		axis.global_transform = Transform3D(Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)), door.global_position)
		var pivot := Node3D.new()
		pivot.name = "DoorPivot"
		axis.add_child(pivot)
		door.reparent(pivot, true)
		var db := _mesh_bounds_in(door, pivot)
		var grab := Area3D.new()
		grab.name = "DoorGrab"
		grab.set_script(load(SCRIPT_HINGE))
		grab.collision_layer = 0
		grab.collision_mask = 0
		grab.set("engage_radius", 0.12)
		pivot.add_child(grab)
		grab.position = db.get_center()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = db.size.max(Vector3(0.03, 0.03, 0.03))
		col.shape = shape
		grab.add_child(col)
	# The board's mount, on the tray when there is one, so the board rides out with it.
	var tray := _part("BoardTrayPivot")
	var holder: Node3D = m
	if tray != null:
		tray.reparent(m, true)
		holder = tray
	var mount := Marker3D.new()
	mount.name = "BayMount"
	holder.add_child(mount)
	mount.global_transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(bay_roll_deg)), anchor.global_position)
	if tray != null and tray_travel > 0.0:
		var tb := _mesh_bounds_in(tray, m)
		var drawer := Area3D.new()
		drawer.name = "TrayHandle"
		drawer.set_script(load(SCRIPT_DRAWER))
		drawer.collision_layer = 0
		drawer.collision_mask = 0
		drawer.set("axis_local", Vector3(0, 0, 1))
		drawer.set("travel", tray_travel)
		# Before it is in the tree: the drawer takes its target's rest where it is when it is ready.
		drawer.set("target", tray)
		# Standing out in front of the tray's lip, so a pointer meets it before the board on the tray (whose own
		# pointer box reaches over the lip).
		drawer.position = Vector3(tb.get_center().x, tb.get_center().y, tb.end.z + 0.02)
		m.add_child(drawer)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(maxf(tb.size.x - 0.04, 0.05), maxf(tb.size.y, 0.03) + 0.02, 0.06)
		col.shape = shape
		drawer.add_child(col)


## Bounds of every mesh under `root`, in `root`'s own space.
static func _mesh_bounds(root: Node3D) -> AABB:
	return _mesh_bounds_in(root, root)


## Bounds of every mesh under `node` (itself included), in `frame`'s space.
static func _mesh_bounds_in(node: Node3D, frame: Node3D) -> AABB:
	var to_frame := frame.global_transform.affine_inverse()
	var acc := AABB()
	var first := true
	for n in [node] + node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var ab: AABB = (to_frame * mi.global_transform) * mi.get_aabb()
		acc = ab if first else acc.merge(ab)
		first = false
	return acc
