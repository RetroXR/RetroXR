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
##   CoinSlot<n>, CoinReturn<n>, ReturnCup<n>                                       player n's coin door (its slot an
##                                                                                  ArcadeCoinSlot, its return a button)
##   BoardDoorPivot (the board's door, swinging about +Y, opening at negative angles) the bay's door, with a hinge to take it by
##   BoardTrayPivot (a tray sliding out along +Z by `tray_travel`)                  a drawer the bay rides on
##   BoardAnchor                                                                    the bay's BayMount: the board (an
##                                                                                  ArcadeBayUnit) clips in there, turned
##                                                                                  by `bay_roll_deg`
##   <Name>DoorPivot (another door, swinging about +Y; hinged on its left edge it      a door of its own that opens, with a
##   opens at negative angles, on its right edge at positive)                       hinge to take it by (<Name>Grab)
##   <Name>HatchPivot (a service hatch hinged along its bottom edge)                 a hatch that drops open outward, about
##                                                                                  the cabinet's X, with a hinge to take it by
##   <Name>LiftOff (a mesh: a panel held by a lock, no hinge)                         a cover you take off and put back
##                                                                                  (CoverSlots), wearing the panel
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
const SCRIPT_COIN_SLOT := "res://Scripts/Objects/arcade/arcade_coin_slot.gd"
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
## The board's turn in its mount about the cabinet's up (+Y), degrees, before the roll: 0 faces its sockets to the cabinet's
## front; 180 to its back (the NAOMI Universal's NAOMI lies with its vents toward the tray's front and its wiring at the back
## end, hard--candy's inside photograph: turned the other way its plugs ran into the tray's lip).
@export var bay_yaw_deg: float = 0.0
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
## Which of the model's variants this cabinet is (a regional build: the NAOMI Universal's JP coin entry on its panel, or its US
## coin door): the model's Variant<name> meshes other than this one are hidden, and a marker is looked for as <name>_<marker>
## first (JP_CoinSlot1), then as itself. Empty: the model as drawn.
@export var variant: String = ""
## Each coin slot's way in, its long side and length, in the model's frame (ArcadeCoinSlot): a coin goes in on edge, in the
## plane of the two. The default is a slot on the top of a coin entry, front to back (the candy cabinets', the AWSD's); a
## coin door's slot in its face is (0, 0, -1) with a vertical (0, 1, 0) long side.
@export var coin_insert_dir := Vector3.DOWN
@export var coin_slot_long := Vector3(0, 0, 1)
@export var coin_slot_length := 0.03

var _model: Node3D = null
## The bodies riding the cabinet that are not it (its doors', its hatches', its tray's): the World layer while it stands, none
## while it is held, so a carried cabinet passes through things as every held object does (HeldObjectPhysics clears the
## cabinet's own body, not these).
var _riding: Array[CollisionObject3D] = []
## The layer those bodies are on: Pickable (3), the cabinet's own. The cords (their surface mask) and loose objects meet them, the
## player does not, as with the cabinet itself and everything else that can be moved. On World (1) a cabinet with its doors
## shut was a wall the player could not walk through (the owner, 2026-11-13).
const RIDING_LAYER := 4
## What a carried cabinet takes along that is not its child: the cords lying in it (VerletRope) and the frozen bodies
## standing in it (a JAMMA cabinet's converter). A held cabinet collides with nothing, so left to themselves the cords
## trailed out through its walls as it moved, and the converter stayed where the cabinet had been.
var _pickable: XRToolsPickable = null
var _carried: Array[Node3D] = []
## Where the machine was last physics frame, and how many frames it has stood still since it last moved. From 0: a cabinet
## only just spawned or restored settles as its cords are laid and plugged in, and moving them then left a captive
## lead's plug out of its socket; nothing is carried until it has once stood still.
var _carry_from := Transform3D.IDENTITY
var _still := 0
## Physics frames standing still before the insides are let go.
const CARRY_SETTLE := 30
## How far the glow on a panel (ArcadePanelGlow) stands clear of its stick and buttons, metres.
const GLOW_CLEAR := 0.012
## How far past its marker a cabinet's own cord looks for the surface its grommet is in, metres.
const CAPTIVE_REACH := 0.15
## The game's own female phono jack (RcaJack), for a cabinet's amplifier inputs.
const RCA_JACK_SCENE := "res://Scenes/Objects/cables/rca_jack.tscn"
## Less than this from one physics frame to the next is standing still (meters, radians).
const CARRY_MOVE := 0.0005


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
	# The other variants' parts out of sight (and out of the bounds the cabinet's size comes from: measured above, with all).
	for v in _model.find_children("Variant*", "Node3D", true, false):
		(v as Node3D).visible = variant.is_empty() or str(v.name) == "Variant" + variant
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
	_build_lift_offs.call_deferred()
	_watch_held.call_deferred()


## The model's lift-off panels (<Name>LiftOff meshes): each a cover slot round the panel, the panel hidden there and worn by the
## cover in it, so it is taken off, put down and put back like a battery cover, and a save keeps whether it is on. Deferred:
## the cabinet must be in its machine (the cover's host) first.
func _build_lift_offs() -> void:
	for n in _model.find_children("*LiftOff", "MeshInstance3D", true, false):
		var part := n as MeshInstance3D
		var zone := CoverSlots.shell_cover(part, "cabinet_" + str(part.name).to_snake_case(), LIFT_OFF_OUT)
		if zone == null:
			continue
		zone.has_picked_up.connect(_dress_lift_off.bind(part))
		if zone.picked_up_object != null:
			_dress_lift_off(zone.picked_up_object, part)


## The way a lift-off panel's face looks: the cabinet's front.
const LIFT_OFF_OUT := Vector3.BACK


func _dress_lift_off(what: Node3D, part: MeshInstance3D) -> void:
	var cover := what as PortCover
	if cover == null or cover.has_node("Shell"):
		return
	var copy := part.duplicate() as MeshInstance3D
	part.get_parent().add_child(copy)
	copy.transform = part.transform
	copy.visible = true
	CoverSlots.wear(cover, copy, LIFT_OFF_OUT)


## A tray's solid parts, riding with it: its floor (the bottom TRAY_FLOOR of its bounds) and its lip across the front (the
## front TRAY_LIP of them, its full height). Not one box of its bounds: that would stand a board on the lip's top.
const TRAY_FLOOR := 0.012
const TRAY_LIP := 0.008


func _tray_body(tray: Node3D) -> void:
	var b := _mesh_bounds_in(tray, tray)
	var body := AnimatableBody3D.new()
	_riding.append(body)
	body.name = "TrayBody"
	body.collision_layer = RIDING_LAYER
	body.collision_mask = 0
	body.sync_to_physics = false
	body.set_meta(InteractionResolver.POINTER_BY_AREA, true)
	for box: AABB in [AABB(b.position, Vector3(b.size.x, minf(TRAY_FLOOR, b.size.y), b.size.z)),
			AABB(Vector3(b.position.x, b.position.y, b.end.z - TRAY_LIP), Vector3(b.size.x, b.size.y, TRAY_LIP))]:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size.max(Vector3(0.005, 0.005, 0.005))
		col.shape = shape
		col.position = box.get_center()
		body.add_child(col)
	_exempt_from_own_cabinet(body)
	tray.add_child(body)


## The cabinet's machine (the pickable it is in): its riding bodies stop colliding while it is held.
func _watch_held() -> void:
	var n: Node = get_parent()
	while n != null and not n is XRToolsPickable:
		n = n.get_parent()
	if n == null:
		return
	var p := n as XRToolsPickable
	_pickable = p
	_carry_from = p.global_transform
	p.picked_up.connect(func(_by: Variant = null) -> void: _set_riding_solid(false))
	p.dropped.connect(func(_by: Variant = null) -> void: _set_riding_solid(true))
	set_physics_process(true)


## What lies inside the cabinet as it stood at `was` (its machine's transform then): every cord whose every point is within
## its drawn bounds, every frozen body (not the cabinet's own) whose origin is.
func _collect_carried(was: Transform3D) -> void:
	_carried.clear()
	if _model == null or _pickable == null:
		return
	var box := _mesh_bounds_in(_model, self).grow(0.03)
	var to_me := (was * (_pickable.global_transform.affine_inverse() * global_transform)).affine_inverse()
	for r in get_tree().root.find_children("*", "VerletRope", true, false):
		var pts: PackedVector3Array = r.call("get_points")
		if pts.is_empty():
			continue
		var all_in := true
		for q in pts:
			if not box.has_point(to_me * q):
				all_in = false
				break
		if all_in:
			_carried.append(r as Node3D)
	for b in get_tree().root.find_children("*", "RigidBody3D", true, false):
		var body := b as RigidBody3D
		# (not what something holds -- the board in its mount -- nor a plug: its socket or its cord moves it, and one moved
		# while it was still going into its socket was left out of it)
		var held := body is CablePlug or (body is XRToolsPickable and (body as XRToolsPickable).is_picked_up())
		if body.freeze and not held and body != _pickable and not _pickable.is_ancestor_of(body) and box.has_point(to_me * body.global_position):
			_carried.append(body)


## Whenever the machine moves -- carried in a hand or on the desktop, stood on the floor, pushed -- what is inside it moves
## the same, from the frame it starts moving until it has stood still CARRY_SETTLE frames.
func _physics_process(_delta: float) -> void:
	if _pickable == null:
		return
	var now := _pickable.global_transform
	var move := now * _carry_from.affine_inverse()
	var moved := move.origin.length() > CARRY_MOVE or move.basis.get_rotation_quaternion().get_angle() > CARRY_MOVE
	if moved:
		if _still >= CARRY_SETTLE:
			_collect_carried(_carry_from)
		_still = 0
		for n in _carried:
			if not is_instance_valid(n):
				continue
			if n is RigidBody3D:
				n.global_transform = move * n.global_transform
			else:
				var pts: PackedVector3Array = n.call("get_points")
				for i in pts.size():
					pts[i] = move * pts[i]
				n.call("restore_points", pts)
	elif _still < CARRY_SETTLE:
		_still += 1
		if _still == CARRY_SETTLE:
			_carried.clear()
	_carry_from = now


func _set_riding_solid(solid: bool) -> void:
	for b in _riding:
		if is_instance_valid(b):
			b.collision_layer = RIDING_LAYER if solid else 0


## A door's solid part: a box over its bounds that swings with it (a body that moves with its pivot), so a cord lies
## against a shut door rather than through it. On the World layer the cords collide with; the desktop pointer sees past
## it (InteractionResolver.POINTER_BY_AREA) to the door's own grab.
func _door_body(pivot: Node3D, bounds: AABB) -> void:
	var body := AnimatableBody3D.new()
	_riding.append(body)
	body.name = "DoorBody"
	body.collision_layer = RIDING_LAYER
	body.collision_mask = 0
	body.sync_to_physics = false
	body.set_meta(InteractionResolver.POINTER_BY_AREA, true)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = bounds.size.max(Vector3(0.005, 0.005, 0.005))
	col.shape = shape
	col.position = bounds.get_center()
	body.add_child(col)
	_exempt_from_own_cabinet(body)
	pivot.add_child(body)


## A door's or tray's body is a CHILD of the cabinet's own RigidBody3D, on the World layer its mask takes, and Godot
## does not exempt a body from its own descendants: every cabinet with one pushed against its own doors for ever and
## flew about the room (1 kg, up to 14 m/s and 26 rad/s, measured in the Starlight Arcade 2026-11-13), dragging its
## cords awake with it -- 11 fps on a Quest. Cords and other objects still meet the part; the cabinet does not.
func _exempt_from_own_cabinet(body: PhysicsBody3D) -> void:
	body.tree_entered.connect(_exempt_now.bind(body))


func _exempt_now(body: PhysicsBody3D) -> void:
	var up := body.get_parent()
	while up != null and not up is PhysicsBody3D:
		up = up.get_parent()
	if up == null:
		push_warning("[ArcadeModel] %s has no cabinet body above it to exempt" % body.name)
		return
	body.add_collision_exception_with(up as PhysicsBody3D)


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
			# The amplifier's phono inputs are the game's own jack (RcaJack, white or red by channel), in place of the
			# model's stand-in blocks; the VGA and JAMMA sockets stay the model's.
			var phono := str(r[3]) == Connectors.PHONO
			if phono:
				# As rca_port.tscn has it: the jack's face 10 mm behind the port, its socket out along +Z.
				var jack := (load(RCA_JACK_SCENE) as PackedScene).instantiate() as Node3D
				jack.position = Vector3(0.0, 0.0, -0.01002)
				port.add_child(jack)
			port.set("show_jack", phono)
		if captive:
			port.set_meta(NaomiHookup.CAPTIVE_META, true)
			port.has_picked_up.connect(_captive_seated.bind(port))
		# The supply's second lead, for a GD-ROM drive, beside the board's.
		if str(r[0]) == "BoardPowerLead":
			var dp := NaomiHookup.make_port(NaomiGdRom.CAB_DRIVE_POWER, "res://Scripts/Objects/cables/port.gd", NaomiHookup.NAOMI_POWER)
			add_child(dp)
			# In the cabinet's frame, not the world's: one built already turned (a save restoring it) had this socket turned by
			# the cabinet's own heading.
			dp.global_transform = Transform3D(global_basis, at.global_position + global_basis * Vector3(0.05, 0.0, 0.0))
		if at.name == "JvsInAnchor":
			at.add_child(port)
		else:
			add_child(port)
			var facing := _lead_facing(str(r[0]), at.global_position)
			var spot := at.global_position
			if captive:
				# A cabinet's own cord comes out of a grommet: its socket sits ON the surface the plug would go into (the base's
				# ceiling), not where the marker floats a few centimetres short of it, which left the cord's end in the air.
				var face: Variant = _surface_along(spot, -facing.z, CAPTIVE_REACH)
				if face != null:
					spot = face as Vector3
			port.global_transform = Transform3D(facing, spot)


## The cabinet end of one of its own cords seated: out of sight in the grommet, and fixed there (neither it nor the
## socket can be taken from). A save brings the cord back seated, and this hides it again.
func _captive_seated(what: Node3D, port: Port) -> void:
	if what == null:
		return
	# The plug sinks into the surface by its own length, so its cord comes out AT the grommet: seated at the surface, its
	# hidden body hung below it and the cord began that far down in the air (50 mm for the VGA plug). Once per socket: a
	# save brings the plug back seated and calls this again.
	if not port.has_meta(&"captive_sunk"):
		var back := 0.0
		var inv := port.global_transform.affine_inverse()
		for m in what.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var box := mi.mesh.get_aabb()
			for i in 8:
				back = maxf(back, (inv * (mi.global_transform * box.get_endpoint(i))).z)
		port.set_meta(&"captive_sunk", back)
		if back > 0.0:
			port.global_position -= port.global_basis.z.normalized() * back
	for m in what.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).visible = false
	if what is XRToolsPickable:
		(what as XRToolsPickable).enabled = false
	port.enabled = false


## The first of the model's own surfaces from `from` along `dir` (world), within `reach` metres; null when none.
func _surface_along(from: Vector3, dir: Vector3, reach: float) -> Variant:
	var to := from + dir.normalized() * reach
	var best: Variant = null
	var best_d := INF
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var inv := mi.global_transform.affine_inverse()
		var a := inv * from
		var b := inv * to
		if not mi.mesh.get_aabb().intersects_segment(a, b):
			continue
		var tri := mi.mesh.generate_triangle_mesh()
		if tri == null:
			continue
		var hit := tri.intersect_segment(a, b)
		if hit.is_empty():
			continue
		var at := mi.global_transform * (hit["position"] as Vector3)
		if at.distance_to(from) < best_d:
			best_d = at.distance_to(from)
			best = at
	return best


## A lead's socket takes its plug along -Z: from the front, or, when the model has a `<lead>Aim` marker, from there.
func _lead_facing(lead: String, at: Vector3) -> Basis:
	var aim := _part(lead + "Aim")
	if aim == null or aim.global_position.is_equal_approx(at):
		# The cabinet's front, not the world's (one built already turned faced the world's).
		return global_basis.orthonormalized()
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
		var line := _part(door_name + "Axis")
		if line != null:
			# A door on a leaning face: its hinge is the line from its pivot to <Name>DoorAxis, and it swings out, its middle moving
			# away from the cabinet's (toward the front for a door on the front).
			var pv := to_local(door.global_position)
			var ax := (to_local(line.global_position) - pv).normalized()
			var mid := mb.get_center()
			if ax.cross(mid - pv).z * signf(mid.z) < 0.0:
				ax = -ax
			var side := ax.cross(Vector3.UP if absf(ax.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
			axis_basis = Basis(ax, side, ax.cross(side).normalized())
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
		_door_body(turn, db)
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
	if not variant.is_empty():
		var own := _model.find_child(variant + "_" + part_name, true, false) as Node3D
		if own != null:
			return own
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
			parts.append(_move(cap, m, "Btn%d" % k))
	if start != null:
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
	# The deck: its plane under the controls, from rays straight down onto the cabinet's own surfaces (the caps' bottoms
	# are under it). A panel can slope (the NAOMI Universal's does, in its meshes, not in its nodes).
	var deck := _deck_frame(m, box)
	# A cap sinks into the deck, along the deck's own up.
	var press := deck.basis.z * -ArcadeControlModule.CAP_PRESS * 0.5
	for p: Node3D in parts:
		if p.name != &"StickPivot":
			p.set_meta(&"press_offset", press)
	# The panel's colour, for its glow and its "1P": the first cap's.
	var tint: Variant = _part_color(parts[1] if parts.size() > 1 else parts[0])
	if tint != null:
		m.set_meta(&"player_color", tint)
	# The glow lies round the stick and the buttons only (not START), a little clear of them.
	var lit := AABB()
	var lit_first := true
	for p: Node3D in parts:
		if p.name == &"Start":
			continue
		var b := _mesh_bounds_in(p, m)
		if b.size == Vector3.ZERO:
			continue
		lit = b if lit_first else lit.merge(b)
		lit_first = false
	box = box.grow(0.03)
	var grip := Area3D.new()
	grip.name = "PanelGrip"
	grip.set_script(load(SCRIPT_GRIP))
	grip.collision_layer = 0
	grip.collision_mask = 0
	grip.set("panel_size", Vector2(box.size.x, box.size.z))
	if not lit_first:
		# The stick and the buttons laid onto the deck, in the grip's XY.
		var inv := deck.affine_inverse()
		var r := Rect2()
		for i in 8:
			var q := inv * lit.get_endpoint(i)
			r = Rect2(Vector2(q.x, q.y), Vector2.ZERO) if i == 0 else r.expand(Vector2(q.x, q.y))
		grip.set_meta(&"glow_rect", r.grow(GLOW_CLEAR))
	# The grip's plane (its XY, facing +Z) lies on the deck: +Z is the deck's up, +Y toward its back. Its glow lies
	# on the deck under the caps; its box stands round the controls as before.
	grip.transform = deck
	m.add_child(grip)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(box.size.x, box.size.z, maxf(box.size.y, 0.06))
	col.shape = shape
	col.position = deck.affine_inverse() * box.get_center()
	grip.add_child(col)


## The deck under a panel's controls, in `m`'s frame: its origin on the deck under the middle of `box`, +Z the deck's up,
## +X across (as `m`'s +X), +Y toward the back. Four rays down round the middle (a quarter of the box each way) give its
## slope; a panel where fewer than three land is level, at the bottom of `box` when none does.
func _deck_frame(m: Node3D, box: AABB) -> Transform3D:
	var c := box.get_center()
	var dx := box.size.x * 0.25
	var dz := box.size.z * 0.25
	var mid: Variant = _deck_point(m, box, c.x, c.z)
	var l: Variant = _deck_point(m, box, c.x - dx, c.z)
	var r: Variant = _deck_point(m, box, c.x + dx, c.z)
	var f: Variant = _deck_point(m, box, c.x, c.z + dz)
	var k: Variant = _deck_point(m, box, c.x, c.z - dz)
	var up := Vector3.UP
	if l != null and r != null and f != null and k != null:
		up = ((r as Vector3) - (l as Vector3)).cross((k as Vector3) - (f as Vector3)).normalized()
	if up.y < 0.0:
		up = -up
	if up.y < 0.5:
		up = Vector3.UP
	var origin := Vector3(c.x, box.position.y, c.z)
	if mid != null:
		origin = mid as Vector3
	elif l != null and r != null:
		origin = ((l as Vector3) + (r as Vector3)) * 0.5
	var x := (Vector3.RIGHT - up * up.x).normalized()
	return Transform3D(Basis(x, up.cross(x), up), origin)


## Where the model's own surfaces (not the panel's controls) are highest straight down at (x, z) of `m`'s frame, from
## above `box` to below it; null where nothing is hit.
func _deck_point(m: Node3D, box: AABB, x: float, z: float) -> Variant:
	var from := m.global_transform * Vector3(x, box.end.y + 0.05, z)
	var to := m.global_transform * Vector3(x, box.position.y - 0.10, z)
	var best: Variant = null
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or m.is_ancestor_of(mi) or not mi.is_visible_in_tree():
			continue
		var inv := mi.global_transform.affine_inverse()
		var a := inv * from
		var b := inv * to
		if not mi.mesh.get_aabb().intersects_segment(a, b):
			continue
		var tri := mi.mesh.generate_triangle_mesh()
		if tri == null:
			continue
		var hit := tri.intersect_segment(a, b)
		if hit.is_empty():
			continue
		var at := m.global_transform.affine_inverse() * (mi.global_transform * (hit["position"] as Vector3))
		if best == null or at.y > (best as Vector3).y:
			best = at
	return best


## A part's colour: its first mesh's first surface's albedo, or null.
static func _part_color(part: Node3D) -> Variant:
	if part == null:
		return null
	for n in part.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var mat := mi.material_override if mi.material_override != null else mi.get_active_material(0)
		if mat is BaseMaterial3D:
			return (mat as BaseMaterial3D).albedo_color
	return null


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


## A coin door's slot (ArcadeCoinSlot) at `at`, its way in and its long side `coin_insert_dir` / `coin_slot_long` turned from
## the model's frame into the door module's. Its pointable box stands out of the slot, against the way in.
func _coin_slot(m: Node3D, at: Vector3) -> Area3D:
	var to_m := m.global_basis.inverse() * _model.global_basis
	var into := (to_m * coin_insert_dir).normalized()
	var s := Area3D.new()
	s.name = "CoinSlot"
	s.set_script(load(SCRIPT_COIN_SLOT))
	s.collision_layer = 0
	s.collision_mask = 0
	s.set("insert_dir", into)
	s.set("slot_long", (to_m * coin_slot_long).normalized())
	s.set("slot_length", coin_slot_length)
	m.add_child(s)
	s.global_position = at
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.05, 0.05, 0.05)
	col.shape = shape
	col.position = -into * 0.012
	s.add_child(col)
	return s


func _build_coin(n: int) -> void:
	var slot := _part("CoinSlot%d" % n)
	if slot == null:
		return
	var m := _module("CoinP%d" % n, SCRIPT_COIN, n - 1)
	_coin_slot(m, slot.global_position)
	var ret := _part("CoinReturn%d" % n)
	if ret != null:
		_button(m, "CoinReturn", ret.global_position, Vector3(0.03, 0.03, 0.03))
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
		# Opening carries the door away from the cabinet's middle: toward the player for a door on the front, backward for
		# one on the back (a New Net City's rear hatch swung into the cabinet).
		var dmid := _mesh_bounds_in(door, self).get_center()
		var dpv := to_local(door.global_position)
		var hx := Vector3(0, -1, 0)
		if hx.cross(dmid - dpv).z * signf(dmid.z) < 0.0:
			hx = -hx
		axis.global_transform = Transform3D(global_basis * Basis(hx, Vector3(-hx.y, 0, 0), Vector3(0, 0, 1)), door.global_position)
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
		_door_body(pivot, db)
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
	# In the cabinet's frame: a world basis here was right only for a cabinet built facing the world's -Z. One built already
	# turned (every cabinet a saved room restores) got a mount turned back by its own heading, and the board seated yawed in it
	# (the owner, 2026-11-13, after several "fixed"s that were all tested on cabinets built at 0 degrees).
	mount.global_transform = Transform3D(global_basis * Basis(Vector3.UP, deg_to_rad(bay_yaw_deg)) * Basis(Vector3.BACK, deg_to_rad(bay_roll_deg)),
		anchor.global_position)
	if tray != null and tray_travel > 0.0:
		var tb := _mesh_bounds_in(tray, m)
		_tray_body(tray)
		var drawer := Area3D.new()
		drawer.name = "TrayHandle"
		drawer.set_script(load(SCRIPT_DRAWER))
		drawer.collision_layer = 0
		drawer.collision_mask = 0
		drawer.set("axis_local", Vector3(0, 0, 1))
		drawer.set("travel", tray_travel)
		# Before it is in the tree: the drawer takes its target's rest where it is when it is ready.
		drawer.set("target", tray)
		# Its origin the tray's front face, shut; its grab box round the tray's front lip (the owner, 2026-11-13: it
		# stood fixed in front of the opening while the tray slid out), from just behind the lip to a little in front of
		# it, so a pointer from the front meets it before the board on the tray. Added to the drawer BEFORE the drawer
		# is in the tree: VRSlider adopts its shape in _ready, and only an adopted shape rides out with the knob.
		drawer.position = Vector3(tb.get_center().x, tb.get_center().y, tb.end.z)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(maxf(tb.size.x - 0.02, 0.05), maxf(tb.size.y, 0.03) + 0.02, TRAY_LIP + 0.03)
		col.shape = shape
		col.position = Vector3(0.0, 0.0, 0.015 - (TRAY_LIP + 0.03) * 0.5)
		drawer.add_child(col)
		m.add_child(drawer)
		# The tray as drawn is its handle: outlined green when a hand or the crosshair is on it, and what the desktop
		# crosshair is held to while dragging (without it the drawer had neither). Its lip is a push face: a fingertip
		# pressing it from in front pushes the tray back in (its face the lip's front).
		var tray_mesh := _first_mesh_in(tray)
		if tray_mesh != null:
			drawer.call("set_handle_mesh", tray_mesh)
		drawer.set("push_face_size", Vector2(tb.size.x, maxf(tb.size.y, 0.03)))
		drawer.set("push_face_offset", 0.0)


static func _first_mesh_in(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _first_mesh_in(c)
		if m != null:
			return m
	return null


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
