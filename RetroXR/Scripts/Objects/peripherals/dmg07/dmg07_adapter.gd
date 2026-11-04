## Dmg07Adapter -- Nintendo's 4 Player Adapter (DMG-07), a primitive stand-in.
##
## From Evan-Amos's photograph of the unit (Wikimedia Commons, public domain;
## docs/dev/gb-link.md "The DMG-07 4 Player Adapter"):
##
##   * A light grey rounded-square box with a round grey-violet label on top.
##   * Player 1's lead is CAPTIVE: it leaves the back, toward the left corner,
##     and ends in the original Game Boy's large link plug.
##   * Three sockets, each in the MIDDLE of a face of its own, under the parting
##     line: player 2 on the left, player 3 on the front, player 4 on the right,
##     PLAYER n lettered on the top beside each, and player 1's lead out of the
##     middle of the back (a listing photograph square-on to an edge, and
##     RetroXR-models nintendo/gb/four-player-adapter; the first stand-in had them
##     toward a corner, misread off the studio photograph). They take the DMG-04's
##     large plug (dmg_link_port), so a Game Boy Color or a later machine reaches
##     one through the DMG-14 adapter, as on the real one.
##   * No switch: "the DMG-07 will not power on until its Player 1 cable is plugged
##     into a Game Boy link port" (Pan Docs).
##
## It is a MACHINE: it runs a core of its own (dmg07, RetroXR/dmg07-libretro),
## kept, as the Game Boy Printer's is (GbPrinter). Socket k is the core's link port
## k, so a lead from a Game Boy to the socket for player k+1 is a wire of two, the
## Game Boy's port 0 and the adapter's port k -- what both Game Boy cores insist a
## cable is. Player 1's port 0 is a socket hidden in the back with one end of an
## ordinary DMG-04 lead seated in it for good: the lead is the room's own LinkCable,
## so seating, the bus and netplay's walk all work on it unchanged, and it is the
## ADAPTER's (kept out of "spawned", saved in the adapter's entry).
##
## The core runs while player 1's plug is in a Game Boy (switched on or not), and
## stops when it comes out: the adapter's power. Every lead on it is told to say
## its wire again whenever it starts or stops (GbPrinter._rejoin_lead).
##
## Sizes are estimates: 85 x 25 x 85 mm, the corners rounded 14 mm.
##
## A mod dresses it (xenu.dmg07): it moves the sockets and Player1Port onto its
## model's anchors after _ready, and dresses the lead's free plug on lead_made.
class_name Dmg07Adapter
extends XRToolsPickable

## Player 1's lead exists (a frame after _ready, as it is added to the room).
signal lead_made(lead: LinkCable)

const CORE := "dmg07"
## Its own scene, not the DMG-04's: see dmg07_lead.tscn.
const LEAD_SCENE := preload("res://Scenes/Objects/cables/dmg07_lead.tscn")

const SIZE := Vector3(0.085, 0.025, 0.085)
const CORNER := 0.014
const SOCKET_Y := 0.011
## Players 2-4: the socket's node, the face it is on (its outward normal, +Z the
## front) and where along that face from its middle, as a fraction of its width,
## positive to the left as seen looking at the face: each in the middle.
const SOCKETS := [
	{"name": "Player2Port", "link_port": 1, "face": Vector3.LEFT, "along": 0.0},
	{"name": "Player3Port", "link_port": 2, "face": Vector3.BACK, "along": 0.0},
	{"name": "Player4Port", "link_port": 3, "face": Vector3.RIGHT, "along": 0.0},
]
## Player 1's lead: out of the middle of the back.
const CORD_X := 0.0

const GREY := Color(0.80, 0.80, 0.78)
const LABEL := Color(0.52, 0.50, 0.58)
const PRINT := Color(0.42, 0.42, 0.44)

## What its menu (ObjectOptionsPanel) is titled.
var display_name := "4 Player Adapter"
## Read by LinkCable._watch, as RetroSystem's and GbPrinter's are.
var is_powered_on := false
## Why net_prepare_boot last refused, in words the session shows the player.
var net_boot_failure: String = ""
## Whether player 1's plug in a Game Boy starts the core. A test seam: a suite
## asks wants_power() and must never start a core.
var auto_power := true

var _lib: Node = null
var _lead: LinkCable = null
var _cord_port: LinkPort = null
var _ports: Array[LinkPort] = []
var _toast: AchievementToast = null
var _said_missing := false
var _poll := 0.0
## Where a restore asked player 1's plug to go, held until the lead exists.
var _pending_lead_seat: Dictionary = {}


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group("dmg07_adapter")
	_build_body()
	_build_sockets()
	_spawn_lead.call_deferred()


func _exit_tree() -> void:
	if is_powered_on and _lib != null:
		_lib.StopContent()
	is_powered_on = false
	# The lead is the adapter's: it goes with it.
	if is_instance_valid(_lead) and not _lead.is_queued_for_deletion():
		_lead.queue_free()
	super._exit_tree()


# --- Body and sockets ------------------------------------------------------------

## A face's basis: +Z out of it (the way a plug arrives from, as every socket's),
## +Y up. Set in code rather than written as a .tscn matrix (CLAUDE.md's trap).
static func face_basis(out: Vector3) -> Basis:
	return Basis(Vector3.UP, atan2(out.x, out.z))


func _build_body() -> void:
	var grey := _material(GREY, 0.6)
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	# The rounded square: a cross of two boxes and a post at each corner.
	var inner := SIZE - Vector3(CORNER * 2.0, 0.0, CORNER * 2.0)
	_box(body, Vector3(SIZE.x, SIZE.y, inner.z), Vector3(0, SIZE.y * 0.5, 0), grey, "BodyX")
	_box(body, Vector3(inner.x, SIZE.y, SIZE.z), Vector3(0, SIZE.y * 0.5, 0), grey, "BodyZ")
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = CORNER
			cyl.bottom_radius = CORNER
			cyl.height = SIZE.y
			cyl.radial_segments = 20
			post.mesh = cyl
			post.material_override = grey
			body.add_child(post)
			post.position = Vector3(sx * inner.x * 0.5, SIZE.y * 0.5, sz * inner.z * 0.5)
	# The round label on top, and its words (no maker's mark).
	var disc := MeshInstance3D.new()
	disc.name = "TopLabel"
	var dcyl := CylinderMesh.new()
	dcyl.top_radius = SIZE.x * 0.33
	dcyl.bottom_radius = SIZE.x * 0.33
	dcyl.height = 0.0008
	dcyl.radial_segments = 40
	disc.mesh = dcyl
	disc.material_override = _material(LABEL, 0.5)
	body.add_child(disc)
	disc.position = Vector3(0, SIZE.y + 0.0004, -0.002)
	var flat := Basis(Vector3.RIGHT, -PI * 0.5)
	# Two short lines, inside the disc (one line ran off it, white on the white body).
	_label(body, "FOUR PLAYER", Transform3D(flat, Vector3(0, SIZE.y + 0.0010, -0.008)), Color(0.94, 0.94, 0.97), 13)
	_label(body, "ADAPTER", Transform3D(flat, Vector3(0, SIZE.y + 0.0010, 0.000)), Color(0.94, 0.94, 0.97), 13)
	# Player numbers at the corners beside each socket, and player 1 by the cord.
	_label(body, "PLAYER 1", Transform3D(flat, Vector3(CORD_X - 0.002, SIZE.y + 0.0004, -SIZE.z * 0.5 + 0.007)), PRINT, 12)
	for s: Dictionary in SOCKETS:
		var out: Vector3 = s["face"]
		var fb := face_basis(out)
		var at := _socket_point(s) + Vector3(0, SIZE.y - SOCKET_Y + 0.0004, 0) - out * 0.007
		_label(body, "PLAYER %d" % (int(s["link_port"]) + 1), Transform3D(fb * flat, at), PRINT, 12)

	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		var box := BoxShape3D.new()
		box.size = SIZE
		shape.shape = box
		shape.position = Vector3(0, SIZE.y * 0.5, 0)


## Where socket `s` sits on its face: the face's middle, moved along the face.
static func _socket_point(s: Dictionary) -> Vector3:
	var out: Vector3 = s["face"]
	var along := Vector3(-out.z, 0, out.x)
	var half := SIZE * 0.5
	var face_at := Vector3(out.x * half.x, SOCKET_Y, out.z * half.z)
	return face_at + along * float(s["along"]) * SIZE.x


func _build_sockets() -> void:
	var port_scene := load("res://Scenes/Objects/cables/dmg_link_port.tscn") as PackedScene
	for s: Dictionary in SOCKETS:
		var port := port_scene.instantiate() as LinkPort
		port.name = str(s["name"])
		port.link_port = int(s["link_port"])
		add_child(port)
		port.transform = Transform3D(face_basis(s["face"]), _socket_point(s))
		port.has_picked_up.connect(_on_plug_seated.bind(port))
		port.has_dropped.connect(_on_plug_pulled.bind(port))
		_ports.append(port)
	# Player 1's: out of the back, holding the captive lead's end. Nothing else
	# goes in it; its plug cannot be taken out (_spawn_lead).
	_cord_port = port_scene.instantiate() as LinkPort
	_cord_port.name = "Player1Port"
	_cord_port.link_port = 0
	add_child(_cord_port)
	_cord_port.transform = Transform3D(face_basis(Vector3.FORWARD), Vector3(CORD_X, SOCKET_Y, -SIZE.z * 0.5))
	_cord_port.has_picked_up.connect(_on_plug_seated.bind(_cord_port))
	var ghost := _cord_port.get_node_or_null("SnapHighlight") as Node3D
	if ghost != null:
		ghost.visible = false
	print("[Dmg07] %s: sockets for players 2-4 on link ports 1-3, player 1's lead on port 0" % name)


## Player 1's lead: an ordinary DMG-04, one end seated in the back for good.
func _spawn_lead() -> void:
	if not is_inside_tree():
		return
	_lead = LEAD_SCENE.instantiate() as LinkCable
	_lead.name = "%sLead" % name
	# NOT "spawned": the adapter's entry records it, and a second entry would
	# restore a second lead.
	get_tree().current_scene.add_child(_lead)
	# Every lead files itself under "spawned" as it enters the tree; this one is
	# the adapter's, saved in its entry, and a second entry would restore twice.
	_lead.remove_from_group("spawned")
	var plug_a := _lead.get_node("PlugA0") as XRToolsPickable
	var plug_b := _lead.get_node("PlugB0") as Node3D
	plug_b.global_position = _cord_port.global_position - global_basis.z * 0.25 + Vector3(0, 0.01, 0)
	_cord_port.pick_up_object(plug_a)
	# Moulded in: a hand cannot take it out, and its shell is the cord's boot.
	plug_a.enabled = false
	for mesh_name: String in ["PlugTip", "PlugNose"]:
		var m := plug_a.get_node_or_null(mesh_name) as Node3D
		if m != null:
			m.visible = false
	_add_boot(plug_a)
	_lead.topology_changed.connect(_check_power)
	print("[Dmg07] %s: player 1's lead made, its end seated in the back" % name)
	lead_made.emit(_lead)
	if not _pending_lead_seat.is_empty():
		var seat := _pending_lead_seat
		_pending_lead_seat = {}
		restore_lead(seat.get("device") as Node3D, str(seat.get("port", "")))
	_check_power()


func _add_boot(plug: Node3D) -> void:
	var boot := MeshInstance3D.new()
	boot.name = "CordBoot"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0032
	cyl.bottom_radius = 0.0048
	cyl.height = 0.012
	boot.mesh = cyl
	boot.material_override = _material(Color(0.12, 0.12, 0.12), 0.7)
	plug.add_child(boot)
	# Along the plug's -Z (out of the back), the wide end against the body.
	boot.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.006))


## A plug seated in a socket touches the body it is in; pulled, it collides again
## (GbPrinter's reason). Kept per socket, so the right exception is undone.
var _held := {}


func _on_plug_seated(what: Node, port: LinkPort) -> void:
	var body := what as PhysicsBody3D
	if body == null:
		return
	add_collision_exception_with(body)
	_held[port] = body


func _on_plug_pulled(port: LinkPort) -> void:
	var body: Variant = _held.get(port)
	if is_instance_valid(body):
		remove_collision_exception_with(body as PhysicsBody3D)
	_held.erase(port)
	_check_power()


# --- Power ------------------------------------------------------------------------

## Player 1's plug is in a machine's socket: the adapter is powered.
func wants_power() -> bool:
	if not is_instance_valid(_lead):
		return false
	var plug := _lead.get_node_or_null("PlugB0") as RcaPlug
	# Out of the tree (a room tearing down takes the lead first), a plug cannot be
	# asked where it sits: seated_port looks the sockets up through the tree.
	if plug == null or not plug.is_inside_tree():
		return false
	var port := plug.seated_port() as LinkPort
	return port != null and port.get_machine() != null


func _physics_process(delta: float) -> void:
	# A Game Boy carried off with the lead still in it moves no plug of ours:
	# looked at twice a second rather than on a signal nobody sends.
	_poll += delta
	if _poll >= 0.5:
		_poll = 0.0
		_check_power()


func _check_power() -> void:
	if not is_inside_tree():
		return
	var want := wants_power() and auto_power
	if want and not is_powered_on:
		_power_on()
	elif not want and is_powered_on:
		_power_off()


func _power_on() -> void:
	if CoreDownloadManager.installed_core_lib(CORE).is_empty():
		if not _said_missing:
			_said_missing = true
			print("[Dmg07] %s: player 1's lead is in a Game Boy but the %s core is not installed" % [name, CORE])
			_notice("Adapter core missing", standalone_blocker())
		return
	if not _ensure_lib():
		return
	print("[Dmg07] %s: player 1's lead is in a Game Boy -- powered, starting %s" % [name, CORE])
	_lib.StartContent(CoreDownloadManager.default_core_root(), CORE, "")
	is_powered_on = true
	_rejoin_leads()


func _power_off() -> void:
	print("[Dmg07] %s: player 1's lead is in no Game Boy -- off" % name)
	if _lib != null:
		_lib.StopContent()
	is_powered_on = false
	_said_missing = false
	_rejoin_leads()


## "" when the core is installed, else where to get it.
func standalone_blocker() -> String:
	if CoreDownloadManager.installed_core_lib(CORE).is_empty():
		return "Download it in OPTIONS > Cores > BIOS / Extras > Game Boy."
	return ""


## Made once and KEPT, as GbPrinter's is: freeing a Libretro node whose emulation
## thread is still unwinding takes the process down.
func _ensure_lib() -> bool:
	if _lib != null:
		return true
	var lib: Object = ClassDB.instantiate("Libretro")
	_lib = lib as Node
	if _lib == null:
		push_warning("[Dmg07] could not instantiate a Libretro node")
		return false
	_lib.name = "AdapterLibretro"
	add_child(_lib)
	return true


## Every lead on the adapter says its wire again: a core starting or stopping
## changes what is on the bus without moving a plug.
func _rejoin_leads() -> void:
	var cables: Array = []
	if is_instance_valid(_lead):
		cables.append(_lead)
	for port: LinkPort in _ports:
		var plug := port.picked_up_object
		if plug == null:
			continue
		var cable: Object = plug.get("cable")
		if is_instance_valid(cable):
			cables.append(cable)
	for cable: Object in cables:
		if cable.has_method("rejoin"):
			cable.call("rejoin")


func _notice(title: String, text: String) -> void:
	if not is_instance_valid(_toast):
		_toast = AchievementToast.attach_to_machine(self)
	if _toast != null:
		_toast.show_notice("4 Player Adapter", title, text)


# --- What the room asks of it -----------------------------------------------------

## Player 1's lead (for saves and tests).
func lead() -> LinkCable:
	return _lead


## The three sockets, players 2-4.
func sockets() -> Array[LinkPort]:
	return _ports


## Where player 1's plug is: {device, port}, or {} when it is loose.
func lead_seat() -> Dictionary:
	if not is_instance_valid(_lead):
		return {}
	for seat: Dictionary in _lead.seating():
		if int(seat.get("end", -1)) == 1 and seat.get("device") != null:
			return {"device": seat["device"], "port": str(seat.get("port", ""))}
	return {}


## Put player 1's plug in `port_name` of `device` (a save's).
func restore_lead(device: Node3D, port_name: String) -> void:
	if not is_instance_valid(_lead):
		_pending_lead_seat = {"device": device, "port": port_name}
		return
	if not is_instance_valid(device) or port_name.is_empty():
		return
	var port := CompositeCable.port_named(device, port_name)
	if port == null:
		push_warning("[Dmg07] %s: no socket %s on %s for player 1's lead" % [name, port_name, device.name])
		return
	print("[Dmg07] %s: restoring player 1's lead into %s/%s" % [name, device.name, port_name])
	port.pick_up_object(_lead.get_node("PlugB0"))


## So RcaPort.get_device() finds an owner for the sockets, which is what a lead's
## save records its plug against. Nothing about picture or sound passes here.
func on_av_topology_changed(_links: Array) -> void:
	pass


func get_libretro_node() -> Node:
	return _lib


func resolve_core_name() -> String:
	return CORE


# Netplay: the adapter would join a session as a member of a Game Boy's group, as
# the printer does, but no session has been run with it. Refused until one has.
func port_holders() -> Array:
	return [self]


func net_rom_md5() -> String:
	return ""


func net_boot_spec(_core: String) -> Dictionary:
	return {"mode": "no_content"}


func net_prepare_boot(_spec: Dictionary) -> bool:
	net_boot_failure = "the 4 Player Adapter is not supported in netplay yet"
	return false


func net_sram_file_bytes() -> PackedByteArray:
	return PackedByteArray()


func net_set_sram(_path: String, _data: PackedByteArray) -> void:
	pass


func net_start_core(_core: String, _port_mask: int, _start_frame: int, _options: Dictionary) -> Node:
	return null


func net_stop_core() -> void:
	pass


func net_play_reset() -> void:
	pass


# --- Drawing helpers ----------------------------------------------------------------

static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


static func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.name = node_name
	parent.add_child(mi)
	mi.position = at
	return mi


static func _label(parent: Node3D, text: String, xform: Transform3D, color: Color, font_size: int) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.pixel_size = 0.0004
	lbl.font_size = font_size
	lbl.modulate = color
	lbl.outline_size = 0
	lbl.double_sided = false
	parent.add_child(lbl)
	lbl.transform = xform
	return lbl
