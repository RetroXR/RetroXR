## RetroSystemModelArcadeCabinet — the Morphing Arcade Cabinet.
##
## One piece: a screen, coin doors, a control panel per player, front sockets for
## extra controllers and light guns, and a bay behind a lower door where the board (a
## MAME/FBNeo ROM drawn as a JAMMA board) is plugged in. Nothing here is specific to
## one cabinet shape: the model collects the ArcadeModules in its scene by TYPE
## (Scripts/Objects/arcade/, contract version ArcadeProfiles.CONTRACT_VERSION) and
## wires them to the RetroSystem. A different cabinet is a different scene (or a mod's
## row in the registry) honouring the same modules; a new kind of control or bay is a
## new module, not a change to this class. docs/dev/arcade.md has the contract.
##
## In code the cabinet is the machine and the board is its media, the way a handheld
## is its own machine and a cartridge its media: pulling the board powers it off.
class_name RetroSystemModelArcadeCabinet
extends RetroSystemModel

## The cabinet's outer box: width x height x depth to the control panel's front, with
## the origin on the floor at the centre of the base.
const SIZE := Vector3(0.66, 1.80, 0.87)
const SIZE_CENTER := Vector3(0.0, 0.90, 0.035)

## The cabinet's shape, set by its scene (Tools/gen/gen_arcade_cabinet.gd): the generic upright's numbers
## are the defaults, a wider shooter with a tall straight screen sets its own. Collision, pointer boxes,
## the speakers and the options panel follow them.
@export var cabinet_width := 0.66
@export var cabinet_height := 1.80
## Where the marquee starts (its underside), and how far forward the monitor's glass and the marquee reach.
@export var marquee_bottom := 1.46
@export var glass_back_z := 0.12      # the front of the pointer box that stands behind the glass
@export var marquee_front_z := 0.18   # the front of the pointer box behind the marquee
## The front of the upper cabinet (above the deck): 0.40 on the generic upright, whose collision is one
## box to there; a straight screen stands further back, and the coin face below it then needs a box of its own.
@export var screen_front_z := 0.40

var _modules: Array[ArcadeModule] = []
var _screen: ArcadeScreenModule = null
var _bay: ArcadeBayModule = null
var _av_in: ArcadeAvInModule = null
var _sockets: ArcadeSocketModule = null
var _controls: Array[ArcadeControlModule] = []
var _coins: Array[ArcadeCoinModule] = []
var _pedals: Array[ArcadePedalModule] = []
var _services: Array[ArcadeServiceModule] = []
var _input: ArcadeInput = null
var _marquee_mat: StandardMaterial3D = null
## The slots a game's art hangs in (gen_arcade_cabinet.gd `_build_art`); null on a scene baked before them.
var _art_marquee: MeshInstance3D = null
var _art_sides: Array[MeshInstance3D] = []
var _marquee_title: Label3D = null
var _art_marquee_mat: StandardMaterial3D = null
var _lit := false
## The System tab's "Cabinet Art": off leaves the cabinet plain whatever is in its bay. What was
## last hung is kept, so switching it back on needs no second read of the disk.
var _art_enabled := true
var _art_wheel: Texture2D = null
var _art_cover: Texture2D = null
## The pointer slab behind a shut door: off while the door is open.
var _pointer_door: CollisionShape3D = null


func _ready() -> void:
	_collect_modules()
	# The row this scene was baked from: what a game's form is derived from, and what it goes back to.
	var variant := str(get_meta(ArcadeCabinetBuilder.VARIANT_META, ""))
	_base_spec = ArcadeCabinetSpecs.variant(variant)
	if not _base_spec.is_empty():
		_base_spec["variant"] = variant
	_form_spec = _base_spec
	ArcadeShadowBudget.trim(self)


## Find the modules by type and attach the ones not attached yet (all of them on the first call; after a
## morph, the form's new ones: the bay and the composite input stay as they were).
func _collect_modules() -> void:
	var known: Dictionary = {}
	for m in _modules:
		if is_instance_valid(m):
			known[m] = true
	_modules.clear()
	_controls.clear()
	_coins.clear()
	_pedals.clear()
	_services.clear()
	_screen = null
	_sockets = null
	for n in find_children("*", "ArcadeModule", true, false):
		var m := n as ArcadeModule
		_modules.append(m)
		if not known.has(m):
			m.attach(self)
			if m is ArcadeServiceModule:
				(m as ArcadeServiceModule).pressed.connect(_on_service_pressed)
		match m.kind:
			ArcadeProfiles.KIND_SCREEN:
				_screen = m as ArcadeScreenModule
			ArcadeProfiles.KIND_BAY:
				_bay = m as ArcadeBayModule
			ArcadeProfiles.KIND_AV_IN:
				_av_in = m as ArcadeAvInModule
			ArcadeProfiles.KIND_SOCKETS:
				_sockets = m as ArcadeSocketModule
			ArcadeProfiles.KIND_STICK_BUTTONS:
				_controls.append(m as ArcadeControlModule)
			ArcadeProfiles.KIND_COIN:
				_coins.append(m as ArcadeCoinModule)
			ArcadeProfiles.KIND_PEDAL:
				_pedals.append(m as ArcadePedalModule)
			ArcadeProfiles.KIND_SERVICE:
				_services.append(m as ArcadeServiceModule)
	_controls.sort_custom(func(a: ArcadeControlModule, b: ArcadeControlModule) -> bool: return a.player < b.player)
	var marquee := find_child("Marquee", true, false) as MeshInstance3D
	_marquee_mat = null
	if marquee != null and marquee.mesh != null and marquee.mesh.material is StandardMaterial3D:
		_marquee_mat = marquee.mesh.material as StandardMaterial3D
	_art_marquee = find_child("MarqueeArt", true, false) as MeshInstance3D
	_marquee_title = find_child("MarqueeTitle", true, false) as Label3D
	_art_sides.clear()
	for n in ["SideArtL", "SideArtR"]:
		var side := find_child(n, true, false) as MeshInstance3D
		if side != null:
			_art_sides.append(side)


func _process(delta: float) -> void:
	for m in _modules:
		m.tick(delta)
	if _watch_descriptors:
		_descriptor_wait -= delta
		if _descriptor_wait <= 0.0:
			_descriptor_wait = DESCRIPTOR_POLL
			_poll_descriptors()


## Where a cabinet's weight is, up from the floor: the heavy base and the board and PSU in the bay,
## not the marquee. Low, so it resists tipping by itself.
const CENTER_OF_MASS_Y := 0.40
## How fast the controller turns a tilted cabinet back upright: the fraction of the tilt it
## corrects each second, and the most it turns at, radians a second.
const RIGHT_RATE := 5.0
const RIGHT_MAX := 3.0
## Under this much tilt (radians, a fifth of a degree) it is upright and the controller rests.
const UPRIGHT_EPS := 0.0035


## While nobody holds it, a cabinet tends to STAND: released upright it stays upright; released
## leaning, or let fall, it turns back up about the horizontal. Its heading (the turn about UP) is
## left alone, the player's to choose. A hand, a frozen or locked cabinet is never touched.
func _physics_process(delta: float) -> void:
	var body := get_parent() as RigidBody3D
	if body == null:
		return
	_update_ghost(body, delta)
	if body.freeze:
		return
	if body.has_method("is_picked_up") and bool(body.call("is_picked_up")):
		return
	var w := right_angular_velocity(body.global_transform.basis.y, body.angular_velocity)
	if not w.is_equal_approx(body.angular_velocity):
		body.angular_velocity = w


## The angular velocity that stands a body upright: `up` is the body's own up, `current` what it
## turns at now. The turn about the world's UP is kept (a spin the player gave it); the rest is
## the correction toward upright, proportional to the tilt and capped. Pure, for the tests.
static func right_angular_velocity(up: Vector3, current: Vector3) -> Vector3:
	var yaw := Vector3.UP * current.dot(Vector3.UP)
	var tilt := up.angle_to(Vector3.UP)
	if tilt < UPRIGHT_EPS:
		return yaw
	var axis := up.cross(Vector3.UP)
	if axis.length_squared() < 1e-8:
		axis = Vector3.RIGHT          # upside down: any horizontal axis will do
	return yaw + axis.normalized() * minf(tilt * RIGHT_RATE, RIGHT_MAX)


## The modules of one kind (ArcadeProfiles.KIND_*), for the probe and the tests.
func modules_of_kind(kind: StringName) -> Array[ArcadeModule]:
	var out: Array[ArcadeModule] = []
	for m in _modules:
		if m.kind == kind:
			out.append(m)
	return out


func arcade_input() -> ArcadeInput:
	return _input


## Is `ctrl` holding, or reaching for, a control on one of this cabinet's panels (ArcadePanelHands.reaching)? RetroSystem
## does not let such a hand pick the cabinet up: the fist round a stick would fill the carry ring.
func hand_busy(ctrl: XRController3D) -> bool:
	for c in _controls:
		if is_instance_valid(c) and c.hand_reaching(ctrl):
			return true
	return false


# ── what this hardware is ───────────────────────────────────────────────────

func brings_own_body() -> bool:
	return true


## Spawned, a cabinet is handed to the hand that asked for it like any machine, and the player
## stands it where they want it (it used to be set on the floor a stride away).
func spawns_on_floor() -> bool:
	return false


## Notices float in front of the monitor, PARALLEL to it (the tube is tilted back, so is the
## notice), half a metre off the glass and clear of the cabinet, so none of it is inside the
## geometry. Taken from the screen's own transform, so it follows the model if the monitor moves.
const TOAST_DISTANCE := 0.5


func toast_anchor() -> Variant:
	var screen := _screen.get_screen() if _screen != null else null
	if screen == null:
		return Vector3(0.0, 1.30, 0.85)
	var xf: Transform3D = global_transform.affine_inverse() * screen.global_transform
	var basis := xf.basis.orthonormalized()
	return Transform3D(basis, xf.origin + basis.z * TOAST_DISTANCE)


## The options panel stands to the cabinet's RIGHT at eye height, readable from the front,
## instead of floating above a 1.8 m box where nobody can see it.
func options_panel_anchor(panel_size: Vector2) -> Variant:
	return Vector3(cabinet_width * 0.5 + 0.12 + panel_size.x * 0.5, 1.2, 0.25)


## Picked up by HOLDING the grab on it for one second, ring filling: a cabinet is not
## something to carry off with a stray squeeze or click.
## The two speakers of an upright, in the cabinet's own space: a stereo pair low in the
## front, either side of the coin door, facing the player (the apron and kick panel, not the
## monitor's height). Left first. SystemAudio puts the voices here when no TV is connected,
## so the sound comes from the cabinet's front rather than from the middle of its body.
## JAMMA itself carries one mono channel; a stereo board uses this pair, and a mono one
## drives both at once. A 3.1 with a centre is not a cabinet layout, so there is none.
const SPEAKER_L := Vector3(-0.22, 0.34, 0.44)
const SPEAKER_R := Vector3(0.22, 0.34, 0.44)


## A third of the width out of the middle: 0.22 on the 0.66 upright, further out on a wider cabinet.
func audio_speaker_positions() -> PackedVector3Array:
	var x := cabinet_width / 3.0
	return PackedVector3Array([Vector3(-x, SPEAKER_L.y, SPEAKER_L.z), Vector3(x, SPEAKER_R.y, SPEAKER_R.z)])


func grab_hold_seconds() -> float:
	return HoldToGrab.DEFAULT_SECONDS


## A 1.8 m cabinet is never THROWN: let go of it with the hand swinging and it would leave at the hand's speed and tumble at its turn, across the room, into whatever stands
## there. It is set down where the hand let go of it (and stood up, ground placement or its own righting).
func throw_scale() -> float:
	return 0.0


# ── guns in holsters ────────────────────────────────────────────────────────

## The gun a gun cabinet wears (Tools/gen/gen_arcade_gun.gd), and where its cord leaves it
## in the gun's own frame: the same number the gun scene has, which a test pins.
const GUN_SCENE := "res://Scenes/Objects/peripherals/arcade_light_gun.tscn"
const GUN_CORD_BOSS := Vector3(0.0, -0.098, 0.056)
## The gun's grab point in its own frame. A snap zone seats an object by its grab point, not
## its origin, so the well is put where the holster's marker AND this point meet: that is what
## leaves the gun's origin exactly on the marker.
const GUN_GRAB := Transform3D(Basis.IDENTITY, Vector3(0.0, -0.040, 0.048))


## The guns this cabinet is WIRED to, one per holster marker, or [] for a cabinet with sockets
## instead. RetroSystem builds them with the machine, hangs them in their holsters and locks
## the ports (the Famicom's pads work the same way).
func captive_controllers() -> Array[String]:
	var out: Array[String] = []
	if _sockets != null:
		var scene := _sockets.gun_scene if not _sockets.gun_scene.is_empty() else GUN_SCENE
		for i in _sockets.holster_count():
			out.append(scene)
	return out


## Where each gun's well is, in this model's frame: the holster marker with the gun's grab
## point on it (see GUN_GRAB), which puts the gun itself on the marker.
func captive_controller_rests() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for h in gun_origins():
		out.append(h * GUN_GRAB)
	return out


## The swivel each gun is FIXED to, in the order of the guns: {"pivot": the marker, "local": the pivot's place in the
## gun's own frame, "lever": whether a hand turns it by where it is}, or {} for a gun that hangs in a holster and
## can be carried (an Operation Wolf Uzi or a Silent Scope rifle never leaves the cabinet: RetroSystem fixes it with
## LightGun.fix_to_mount).
func captive_gun_mounts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _sockets == null:
		return out
	for i in _sockets.holster_count():
		var pivot := _sockets.pivot_node(i)
		if pivot == null:
			out.append({})
			continue
		var rest := _sockets.find_child("Holster%d" % (i + 1), true, false) as Node3D
		out.append({"pivot": pivot, "local": rest.global_basis.inverse() * (pivot.global_position - rest.global_position),
			"lever": bool(pivot.get_meta("lever", false))})
	return out


## Where each gun's origin hangs, in this model's frame: the holster markers.
func gun_origins() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if _sockets == null:
		return out
	var inv := global_transform.affine_inverse()
	for i in _sockets.holster_count():
		out.append(inv * _sockets.holster_transform(i))
	return out


## Each cord at rest, from the gun's butt to where it goes into the cabinet: down the front,
## round a U near the floor and back up to the entry. A gun hung in its holster is a few
## centimetres from the hole its metre and a half of cord goes into, and the straight line
## between the two would pack the cord into arches; the U spends the length instead. How deep
## it goes is solved against the rope's own length.
func captive_cord_routes(length: float) -> Array:
	var out: Array = []
	if _sockets == null:
		return out
	var inv := global_transform.affine_inverse()
	var origins := gun_origins()
	for i in origins.size():
		var boss: Vector3 = origins[i] * GUN_CORD_BOSS
		var entry: Vector3 = inv * _sockets.cord_entry(i)
		out.append(_gun_route(boss, entry, length))
	return out


func _gun_route(boss: Vector3, entry: Vector3, length: float) -> PackedVector3Array:
	var lo := 0.03                       # lowest the U may go: just off the floor
	var hi := minf(boss.y - 0.25, 0.55)
	if CaptiveCord.polyline_length(_gun_route_at(boss, entry, lo)) <= length:
		return _gun_route_at(boss, entry, lo)
	if CaptiveCord.polyline_length(_gun_route_at(boss, entry, hi)) >= length:
		return _gun_route_at(boss, entry, hi)
	for _i in 24:
		var mid := (lo + hi) * 0.5
		# The higher the bottom of the U, the shorter the cord it uses.
		if CaptiveCord.polyline_length(_gun_route_at(boss, entry, mid)) > length:
			lo = mid
		else:
			hi = mid
	return _gun_route_at(boss, entry, (lo + hi) * 0.5)


func _gun_route_at(boss: Vector3, entry: Vector3, bottom: float) -> PackedVector3Array:
	var x := boss.x
	var down_z := boss.z + 0.06
	var up_z := boss.z - 0.045
	return PackedVector3Array([
		boss,
		Vector3(x, boss.y - 0.03, boss.z + 0.03),
		Vector3(x, boss.y - 0.09, down_z),
		Vector3(x, bottom + 0.06, down_z),
		Vector3(x, bottom, (down_z + up_z) * 0.5),
		Vector3(x, bottom + 0.06, up_z),
		Vector3(x, 0.45, up_z - 0.12),
		Vector3(entry.x, 0.50, entry.z + 0.07),
		Vector3(entry.x, entry.y - 0.05, entry.z + 0.025),
		Vector3(entry.x, entry.y - 0.012, entry.z + 0.006),
		entry,
	])


func get_builtin_screen() -> MeshInstance3D:
	return _screen.get_screen() if _screen != null else null


func channel_screens() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if _screen != null and _screen.get_screen() != null:
		out.append(_screen.get_screen())
	return out


## The cabinet says how many sockets it has; SystemInfo's native_ports is the
## console's and does not get a vote.
func get_controller_port_count() -> int:
	return _sockets.seat_count() if _sockets != null else 0


func port_count_is_fixed() -> bool:
	return true


func configure_controller_ports(port_zones: Array) -> void:
	if _sockets != null:
		_sockets.seat_zones(port_zones)
	hide_port_placeholders(port_zones)


## The base the cabinet stands on, for setting it down by pointing at the floor (GroundPlacement): the
## shell's width by its 0.80 m depth, origin in the middle on the floor, or the rectangle its form covers
## (a cockpit, a stage: ArcadeCabinetBuilder.FOOTPRINT_META).
func ground_footprint() -> Vector2:
	return _footprint_rect().size


## Where the middle of that rectangle is, (x, z) in the cabinet's frame: the origin for the shell alone.
func ground_footprint_center() -> Vector2:
	return _footprint_rect().get_center()


func _footprint_rect() -> Rect2:
	var shell := Rect2(Vector2(-cabinet_width * 0.5, -0.40), Vector2(cabinet_width, 0.80))
	return get_meta(ArcadeCabinetBuilder.FOOTPRINT_META, shell) as Rect2


func _add_ground_placement() -> void:
	var sys := get_parent()
	if sys == null or sys.get_node_or_null("GroundPlacement") != null:
		return
	var placer := GroundPlacement.new()
	placer.name = "GroundPlacement"
	placer.host = sys as Node3D
	placer.set_footprint(ground_footprint(), ground_footprint_center())
	sys.add_child.call_deferred(placer)


## The rectangle on the floor follows the form.
func _refresh_ground_placement() -> void:
	var sys := get_parent()
	var placer := sys.get_node_or_null("GroundPlacement") as GroundPlacement if sys != null else null
	if placer != null:
		placer.set_footprint(ground_footprint(), ground_footprint_center())


func configure_cartridge_slot(slot: Node3D) -> void:
	_add_ground_placement()
	if _bay != null:
		_bay.configure_slot(slot)
		var marker := _bay.mount_marker()
		if marker != null:
			_build_bay_mount(marker)


# ── the bay is a separate object ─────────────────────────────────────────────

const SNAP_ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")

## The compartment's mount: a snap zone that takes an ArcadeBayUnit and holds it rigid, the way the
## 32X's accessory mount holds a spacer. Null on a cabinet whose scene has no `BayMount`.
var _mount: XRToolsSnapZone = null
## The bay clipped in, kept so its collision exception can be undone after it is gone.
var _docked: ArcadeBayUnit = null


## A snap zone at the mount marker. 12 cm of reach: the bay is a box a hand brings, and the zone
## sits in a compartment whose door is the only way to it.
func _build_bay_mount(marker: Node3D) -> void:
	_mount = SNAP_ZONE_SCENE.instantiate() as XRToolsSnapZone
	_mount.name = "BayMountZone"
	_mount.snap_require = ArcadeBayUnit.GROUP
	_mount.grab_distance = 0.12
	_mount.snap_filter = _accepts_bay
	marker.add_child(_mount)
	_mount.has_picked_up.connect(_on_bay_docked)
	_mount.has_dropped.connect(_on_bay_undocked)
	var sys := get_parent()
	if sys != null and not bool(sys.get("_restoring_from_save")):
		_seed_default_bay.call_deferred()


## One bay in the mount, and only one this cabinet could be playing: not one a cable already gives
## to another cabinet.
func _accepts_bay(obj: Node3D) -> bool:
	var unit := obj as ArcadeBayUnit
	if unit == null:
		return false
	var host := unit.get_host()
	return host == null or host == get_parent()


## A fresh cabinet comes with its own kind of bay already in the mount -- never on a restore, which
## is the whole truth about what is in there (the saved bay, a different one, or none).
func _seed_default_bay() -> void:
	if _mount == null or not is_instance_valid(_mount) or _mount.has_snapped_object():
		return
	var kind := _bay.bay_kind if _bay != null else ArcadeProfiles.BAY_JAMMA
	var packed := ArcadeBayUnit.scene_for(kind)
	var sys := get_parent() as Node3D
	if packed == null or sys == null or not sys.is_inside_tree():
		return
	var unit := packed.instantiate() as ArcadeBayUnit
	# Where an expansion's default occupant goes: the room. A test builds its machines under a root of
	# its own, so the machine's own parent is the fallback.
	var home: Node = sys.get_tree().current_scene
	if home == null:
		home = sys.get_parent()
	home.add_child(unit)
	unit.global_position = sys.global_position
	_mount.pick_up_object(unit)


## Put a saved bay back in the mount (RetroSystem.restore_bay), bypassing the reach.
func restore_bay_mount(unit: ArcadeBayUnit) -> void:
	if _mount != null and unit != null:
		_mount.pick_up_object(unit)


## The bay in the mount, or null.
func docked_bay() -> ArcadeBayUnit:
	return _docked if is_instance_valid(_docked) else null


func _on_bay_docked(what: Node3D) -> void:
	var unit := what as ArcadeBayUnit
	var sys := get_parent() as RetroSystem
	if unit == null or sys == null:
		return
	_docked = unit
	# It stands inside the cabinet's own box: neither pushes the other.
	sys.add_collision_exception_with(unit)
	sys.link_bay(unit, ArcadeBayUnit.DOCK)


func _on_bay_undocked() -> void:
	var unit := _docked
	_docked = null
	var sys := get_parent() as RetroSystem
	if sys == null:
		return
	if is_instance_valid(unit):
		sys.remove_collision_exception_with(unit)
	if sys.bay_link_kind() == ArcadeBayUnit.DOCK:
		sys.unlink_bay(null)


## RetroSystem told us a bay is the one now in use: the door gates a docked bay's slot (a cabled
## one stands open to whoever reaches it).
func on_bay_linked(bay: ArcadeBayUnit, how: String) -> void:
	if _bay == null:
		return
	if how == ArcadeBayUnit.DOCK:
		_bay.set_gated_slot(bay.slot)
	else:
		_bay.set_gated_slot(null)
		bay.slot.enabled = true


func on_bay_unlinked(_bay_unit: ArcadeBayUnit) -> void:
	if _bay != null:
		_bay.set_gated_slot(null)


## What the screen shows: the board's picture, or -- while the compartment holds no unit -- whatever machine is
## cabled to the cabinet's composite input (ArcadeAvInModule.external_picture). Nothing cabled, nothing in
## the bay: the dark tube, as before.
func host_picture() -> Texture2D:
	if _attracting():
		return get_parent().call("attract_picture") as Texture2D
	var own := super.host_picture()
	if _av_in == null:
		return own
	var ext := _av_in.external_picture()
	return ext if ext != null else own


## The cabinet is on and only SHOWING its game (RetroSystem.attracting): no core runs, the glass shows the
## game's video or its still.
func _attracting() -> bool:
	var host := get_parent()
	return host != null and bool(host.get("attracting")) and host.has_method("attract_picture")


## True while the glass shows the attract's picture (its aspect is the picture's own).
func attract_picture_active() -> bool:
	return _attracting() and get_parent().call("attract_picture") != null


## True while the screen is showing a cabled machine rather than the board (its aspect is the picture's own).
func external_picture_active() -> bool:
	return _av_in != null and _av_in.external_picture() != null


## The cabinet's composite input block, or null on a cabinet that has none.
func av_in() -> ArcadeAvInModule:
	return _av_in


## RetroSystem told us a cord moved on one of the cabinet's A/V sockets.
func on_av_in_changed() -> void:
	if _av_in != null:
		_av_in.refresh()


## The cabinet is playing a different system now (RetroSystem.link_bay): the panels read their key
## and button maps by system, so they are read again.
func on_machine_system_changed() -> void:
	if _input != null:
		_input.reload_bindings()


func configure_cable_attach(attach_point: Node3D) -> void:
	# A cabinet has no video-out cord: its monitor is part of it.
	attach_point.visible = false


## The generic power button goes inside the bay, beside the board, where the switch
## is on a real cabinet. Reset and open have nothing to do here.
func configure_buttons(power_btn: VRButton, reset_btn: VRButton, eject_btn: VRButton) -> void:
	reset_btn.set_active(false)
	reset_btn.hide()
	eject_btn.set_active(false)
	eject_btn.hide()
	var seat: Node3D = _bay.power_switch_seat() if _bay != null else null
	if seat != null:
		power_btn.global_transform = seat.global_transform
	var lbl := power_btn.get_node_or_null("ButtonLabel") as Label3D
	if lbl != null:
		lbl.hide()


## One box per solid part, leaving the bay open so a board can be carried into it.
## A single box would have kept every hand and board out of the cabinet it plugs into. Run again after a
## morph (the shape may be another): the boxes it added the last time go first.
func configure_collision(host: Node3D) -> void:
	for child in host.get_children():
		if child is CollisionShape3D and str(child.name).begins_with("CabinetBox"):
			host.remove_child(child)
			child.queue_free()
	var w := cabinet_width
	var hw := w * 0.5
	var boxes: Array[AABB] = [
		AABB(Vector3(-hw, 0.00, -0.40), Vector3(w, 0.10, 0.80)),      # base
		AABB(Vector3(-hw, 0.10, -0.40), Vector3(0.02, 0.40, 0.80)),      # left of the bay
		AABB(Vector3(hw - 0.02, 0.10, -0.40), Vector3(0.02, 0.40, 0.80)),       # right of the bay
		AABB(Vector3(-hw, 0.10, -0.40), Vector3(w, 0.40, 0.02)),      # behind the bay
		# The upper body is a HOLLOW shell, not a block: a player leaning into the cabinet reaches the bay
		# from above (the compartment has no ceiling), and a solid block over it was an invisible wall.
		AABB(Vector3(-hw, 0.50, -0.40), Vector3(0.02, cabinet_height - 0.50, screen_front_z + 0.40)),      # left wall
		AABB(Vector3(hw - 0.02, 0.50, -0.40), Vector3(0.02, cabinet_height - 0.50, screen_front_z + 0.40)),      # right wall
		AABB(Vector3(-hw, 0.50, -0.40), Vector3(w, cabinet_height - 0.50, 0.02)),      # back wall
		AABB(Vector3(-hw, 0.50, screen_front_z - 0.05), Vector3(w, cabinet_height - 0.50, 0.05)),      # front wall
		AABB(Vector3(-hw, cabinet_height - 0.02, -0.40), Vector3(w, 0.02, screen_front_z + 0.40)),      # roof
		AABB(Vector3(-hw, 0.78, 0.40), Vector3(w, 0.14, 0.07)),       # control panel overhang
	]
	# A straight screen stands back from the coin face: the front between them needs its own box.
	if screen_front_z < 0.40:
		boxes.append(AABB(Vector3(-hw, 0.50, screen_front_z), Vector3(w, 0.50, 0.40 - screen_front_z)))
	# What the shape adds to the shell: a sit-down cabinet's hood over the door's swing and the wedge of glass in front of its housing.
	var solid: Array = get_meta(ArcadeCabinetBuilder.SOLID_BOXES_META, [])
	for k in solid.size():
		boxes.append(solid[k] as AABB)
	var first := host.get_node_or_null("CollisionShape3D") as CollisionShape3D
	for i in boxes.size():
		var col: CollisionShape3D = first if i == 0 else CollisionShape3D.new()
		if col == null:
			continue
		var shape := BoxShape3D.new()
		shape.size = boxes[i].size
		col.shape = shape
		col.position = boxes[i].get_center()
		if i > 0:
			col.name = "CabinetBox%d" % i
			host.add_child(col)
	_build_pointer_shapes(host)


## What a pointer (the desktop reticle, a laser) hits when it is aimed at the cabinet
## itself. One box over the whole cabinet would hit FIRST, and hide behind its front face
## every door, button and coin slot on it: a ray stops at the nearest thing, and the
## widgets are on the same layer. So these boxes stand BEHIND everything that can be
## operated: the lower block behind the door's back face, the apron behind the sockets,
## the deck and monitor behind the deck's back edge. Pointing at plain panel still
## reaches the cabinet, and pointing at a control reaches the control.
func _build_pointer_shapes(host: Node3D) -> void:
	var area := host.get_node_or_null("PointerArea") as Node3D
	if area == null:
		return
	for child in area.get_children():
		var n := str(child.name)
		if child is CollisionShape3D and (n.begins_with("PointerBox") or n.begins_with("FormBox") or n == "PointerDoor"):
			area.remove_child(child)
			child.queue_free()
	var first := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var w := cabinet_width
	var hw := w * 0.5
	var boxes: Array[AABB] = [
		AABB(Vector3(-hw, 0.00, -0.40), Vector3(w, 0.10, 0.77)),   # base, under the bay
		AABB(Vector3(-hw, 0.10, -0.40), Vector3(0.03, 0.40, 0.77)),   # left of the bay
		AABB(Vector3(hw - 0.03, 0.10, -0.40), Vector3(0.03, 0.40, 0.77)),    # right of the bay
		AABB(Vector3(-hw, 0.10, -0.40), Vector3(w, 0.40, 0.03)),   # behind the bay
		# The upper body is a hollow shell for a pointer too (the compartment is open to the top, and a
		# player leaning in aims down into it): both side walls, the back (which a ray from the front, past
		# every control, still ends on, so pointing at plain panel reaches the cabinet as before) and the roof.
		AABB(Vector3(-hw, 0.50, -0.40), Vector3(0.03, cabinet_height - 0.50, 0.84)),   # left wall
		AABB(Vector3(hw - 0.03, 0.50, -0.40), Vector3(0.03, cabinet_height - 0.50, 0.84)),   # right wall
		AABB(Vector3(-hw, 0.50, -0.40), Vector3(w, cabinet_height - 0.50, 0.03)),   # back wall
		AABB(Vector3(-hw, cabinet_height - 0.03, -0.40), Vector3(w, 0.03, 0.84)),   # roof
		# The front, as thin plates BEHIND everything that can be operated (the coin face, the apron, the
		# glass, the marquee), so a ray from the front still ends on the cabinet where it is aimed at plain
		# panel, and a ray from inside, aimed down into the bay, is not stopped by any of them.
		# Starts 5 cm above the compartment's top: the bay is a JAMMA shelf on a CD-ROM bay (DRIVE_H), so the
		# board stands that much higher and a ray aimed down at it from the front passes just under this plate.
		AABB(Vector3(-hw, 0.55, 0.30), Vector3(w, 0.23, 0.08)),   # coin area
		AABB(Vector3(-hw, 0.78, 0.30), Vector3(w, 0.14, 0.14)),   # apron
		AABB(Vector3(-hw, 0.92, glass_back_z - 0.05), Vector3(w, marquee_bottom - 0.92, 0.05)),   # behind the glass
		AABB(Vector3(-hw, marquee_bottom, marquee_front_z - 0.05), Vector3(w, cabinet_height - marquee_bottom, 0.05)),   # marquee
	]
	for i in boxes.size():
		var col: CollisionShape3D = first if i == 0 else CollisionShape3D.new()
		if col == null:
			continue
		var shape := BoxShape3D.new()
		shape.size = boxes[i].size
		col.shape = shape
		col.position = boxes[i].get_center()
		if i > 0:
			col.name = "PointerBox%d" % i
			area.add_child(col)
	# What the form adds beyond the shell (a cockpit's seat and dash, a stage, deck wings): aimed at, the
	# cabinet. No collision for them (configure_collision): a player walks into a cockpit or onto a stage.
	var form_boxes: Array = get_meta(ArcadeCabinetBuilder.FORM_BOXES_META, [])
	for k in form_boxes.size():
		var fb: AABB = form_boxes[k]
		var fcol := CollisionShape3D.new()
		fcol.name = "FormBox%d" % (k + 1)
		var fshape := BoxShape3D.new()
		fshape.size = fb.size
		fcol.shape = fshape
		fcol.position = fb.get_center()
		area.add_child(fcol)
	# A slab behind the SHUT door, so a pointer aimed at it finds the cabinet (to pick it
	# up) and not the board standing in the bay behind it. Out of the way once it is open.
	_pointer_door = CollisionShape3D.new()
	_pointer_door.name = "PointerDoor"
	var slab := BoxShape3D.new()
	slab.size = Vector3(0.60, 0.40, 0.04)
	_pointer_door.shape = slab
	_pointer_door.position = Vector3(0.0, 0.30, 0.35)
	_pointer_door.disabled = is_lid_open()
	area.add_child(_pointer_door)
	if _bay != null and not _bay.door_changed.is_connected(_on_door_changed):
		_bay.door_changed.connect(_on_door_changed)


func _on_door_changed(open: bool) -> void:
	if is_instance_valid(_pointer_door):
		_pointer_door.disabled = open


## Called by RetroSystem once the cabinet is parented and built: the input node lives
## on the system (the model cannot add a sibling of itself from its own _ready), and
## the cabinet stays where it was put once it comes to rest.
func attach_to_host(host: Node3D) -> void:
	# The console's floating name tag has nowhere sensible to hang on a 1.8 m cabinet;
	# the marquee is where a cabinet says what it is.
	var tag := host.get_node_or_null("SystemNameLabel") as Node3D
	if tag != null:
		tag.hide()
	_input = ArcadeInput.new()
	_input.name = "ArcadeInput"
	host.add_child(_input)
	var coins: Array = []
	for c in _coins:
		coins.append(c)
	var controls: Array = []
	for c in _controls:
		controls.append(c)
	_input.setup(host, self, controls, coins, _pedals.duplicate())
	_input.first_use.connect(func(kind: StringName) -> void:
		if is_instance_valid(host) and host.has_method("attract_first_use"):
			host.call("attract_first_use", kind))
	# While it is in a hand it turns see-through, so the player can see the room behind a
	# 1.8 m box they are carrying. Per-instance dithered transparency, not a transparent
	# material: no sorting, no blending of a huge surface, and no material to swap and restore.
	if host.has_signal("grabbed"):
		host.connect("grabbed", _on_host_grabbed)
		host.connect("dropped", _on_host_dropped)
	# A cabinet is meant to be MOVED: it can be picked up and carried like any machine, and it
	# always comes to STAND: its weight is low (a heavy base), and while nobody holds it a gentle
	# controller turns it back upright about the horizontal, leaving its heading alone
	# (_physics_process). The old yaw-only axis lock kept whatever tilt it was let go at.
	# (The lock in the object's options still pins it where it stands.)
	if host is RigidBody3D:
		var body := host as RigidBody3D
		body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		body.center_of_mass = Vector3(0.0, CENTER_OF_MASS_Y, 0.0)
		body.angular_damp = maxf(body.angular_damp, 2.0)


## How see-through the cabinet is while carried: 0 solid, 1 invisible.
const HELD_TRANSPARENCY := 0.65


func _on_host_grabbed(_pickable: Variant = null, _by: Variant = null) -> void:
	print("[ArcadeCabinet] grabbed: going see-through (per-instance fade=%s)" % str(_per_instance_fade()))
	_signal_held = true
	_ghost_on = true
	_set_transparency(HELD_TRANSPARENCY)


## Let go: it stays a ghost while it settles (`_update_ghost` takes it from there), so a cabinet that
## is dropped, thrown or pushed does not flash solid in front of the face on its way down.
func _on_host_dropped(_pickable: Variant = null) -> void:
	_signal_held = false
	_ghost_settle = GHOST_SETTLE


## A ghost while it is carried, however it was picked up (the signals can miss a path: a ray pull, a
## spawn handed to a hand, the hold ring), and while it MOVES: pushed, dropped or falling, until it has
## been still for GHOST_SETTLE seconds. Read off the body each physics tick, which costs nothing.
const GHOST_SETTLE := 0.6
const GHOST_SPEED := 0.15
var _signal_held := false
var _ghost_settle := 0.0
var _ghost_on := false


## Held by the VR ray (the laser grab), which is its own state in this fork's hand: the body is frozen
## and moved onto its picked-up layer, but `pick_up()` is never called, so no `grabbed` is emitted and
## `is_picked_up()` stays false (measured on the Quest: a cabinet carried that way stayed solid while
## the signal paths saw nothing). The layer is the tell: any hold puts the body on `picked_up_layer`,
## and a release puts it back on `original_collision_layer`.
static func _ray_held(body: RigidBody3D) -> bool:
	if not ("picked_up_layer" in body and "original_collision_layer" in body):
		return false
	var held_layer: int = body.get("picked_up_layer")
	return body.collision_layer == held_layer and body.collision_layer != int(body.get("original_collision_layer"))


func _update_ghost(body: RigidBody3D, delta: float) -> void:
	var held := _signal_held or (body.has_method("is_picked_up") and bool(body.call("is_picked_up"))) \
		or _ray_held(body)
	var moving := not body.freeze and body.linear_velocity.length() > GHOST_SPEED
	if held or moving:
		_ghost_settle = GHOST_SETTLE
	else:
		_ghost_settle = maxf(0.0, _ghost_settle - delta)
	var want := held or _ghost_settle > 0.0
	# A bay docked or a board seated while it is a ghost (a fresh cabinet seeds its bay a moment after it
	# spawns, which is exactly when it is in the hand) is dressed too.
	if want and _ghost_on:
		_relay_ghost()
	if want != _ghost_on:
		_ghost_on = want
		print("[ArcadeCabinet] %s (held=%s moving=%s)" % ["see-through" if want else "solid again", str(held), str(moving)])
		_set_transparency(HELD_TRANSPARENCY if want else 0.0)


func _set_transparency(amount: float) -> void:
	if _per_instance_fade():
		for n in find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).transparency = amount
		return
	_set_ghost_materials(amount)


## Whether this renderer honours GeometryInstance3D.transparency. Forward+ does. The Quest runs the
## mobile renderer, where a cabinet that was set to 0.65 stayed fully solid (reported 2026-10-21, a
## 1.8 m box in front of the face), and the Compatibility renderer ignores it by its own docs.
func _per_instance_fade() -> bool:
	return RenderingServer.get_current_rendering_method() not in ["mobile", "gl_compatibility"]


## The same look without the per-instance fade, done by a shader of our own: each opaque part wears,
## while held, a copy of its material that DISCARDS most pixels in a fixed screen-space dither (no
## alpha, no sorting and no blending of a huge surface, so nothing for a renderer to ignore: the
## `ALPHA_HASH` copies this replaced were reported to leave the cabinet solid on the Quest, cause not
## found, which is why the grab logs what it did).
##
## It covers everything that moves with the cabinet, not only the model: the machine's own parts (the
## power button), the docked bay with the board standing in it, and the guns hanging in their
## holsters (`_ghost_roots`). Per part: a `material_override` or a surface material that is a
## BaseMaterial3D (the baked scene's, or one set from code) is swapped for a shared copy; a part with
## no material wears a default grey; a ShaderMaterial (the monitor's picture, a board's sticker) cannot
## be dithered, so that part is HIDDEN while the cabinet is a ghost; a Label3D is faded by its
## modulate (text is small and a blend costs nothing). Shadows are switched off on every mesh. Each
## change is recorded in `_ghosted`, so it can be undone exactly.
func _set_ghost_materials(amount: float) -> void:
	if amount <= 0.0:
		for entry: Dictionary in _ghosted:
			var node: Node = entry["node"]
			if not is_instance_valid(node):
				continue
			match String(entry["kind"]):
				"override":
					(node as MeshInstance3D).material_override = entry["original"] as Material
				"surface":
					(node as MeshInstance3D).set_surface_override_material(int(entry["surface"]), entry["original"] as Material)
				"hide":
					(node as Node3D).visible = true
				"label":
					(node as Label3D).modulate = entry["original"] as Color
				"shadow":
					(node as GeometryInstance3D).cast_shadow = int(entry["original"]) as GeometryInstance3D.ShadowCastingSetting
		_ghosted.clear()
		return
	if not _ghosted.is_empty():
		return
	var cache: Dictionary = {}
	var plain := StandardMaterial3D.new()
	plain.albedo_color = Color(0.78, 0.78, 0.8)
	var roots := _ghost_roots()
	_ghost_root_count = roots.size()
	for root: Node in roots:
		for n in root.find_children("*", "GeometryInstance3D", true, false):
			_ghost_part(n as GeometryInstance3D, amount, cache, plain)
	print("[ArcadeCabinet] held: %d changes over %d materials (renderer %s)"
		% [_ghosted.size(), cache.size(), RenderingServer.get_current_rendering_method()])


## Whatever moves with the cabinet and draws: the machine node (this model, its power button...), the
## bay docked in it with the board in its slot, and each gun that is hanging in its holster.
func _ghost_roots() -> Array[Node]:
	var roots: Array[Node] = []
	var host := get_parent()
	roots.append(host if host != null else self)
	if host != null and host.has_method("get_bay"):
		var bay: Node = host.call("get_bay")
		if bay != null:
			roots.append(bay)
			var slot: Variant = bay.get("slot")
			if slot is XRToolsSnapZone and is_instance_valid((slot as XRToolsSnapZone).picked_up_object):
				roots.append((slot as XRToolsSnapZone).picked_up_object)
	if host != null and host.has_method("captive_controllers"):
		for gun: Variant in host.call("captive_controllers"):
			var well: Variant = gun.get("captive_well") if gun is Node else null
			if well is XRToolsSnapZone and (well as XRToolsSnapZone).picked_up_object == gun:
				roots.append(gun as Node)
			elif gun is LightGun and (gun as LightGun).is_mounted():
				# A gun on a swivel mount is part of the cabinet and goes see-through with it.
				roots.append(gun as Node)
	return roots


func _ghost_part(g: GeometryInstance3D, amount: float, cache: Dictionary, plain: BaseMaterial3D) -> void:
	# No shadow from a ghost: the shadow pass over a 1.8 m box is the dearest thing it does.
	if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_ghosted.append({"kind": "shadow", "node": g, "original": int(g.cast_shadow)})
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if g is Label3D:
		var label := g as Label3D
		_ghosted.append({"kind": "label", "node": label, "original": label.modulate})
		label.modulate = Color(label.modulate.r, label.modulate.g, label.modulate.b, label.modulate.a * (1.0 - amount))
		return
	var mi := g as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	if mi.material_override != null:
		if mi.material_override is BaseMaterial3D:
			_ghosted.append({"kind": "override", "node": mi, "original": mi.material_override})
			mi.material_override = _ghost_of(mi.material_override as BaseMaterial3D, amount, cache)
		else:
			_hide(mi)
		return
	for i in mi.mesh.get_surface_count():
		var current: Material = mi.get_surface_override_material(i)
		if current == null:
			current = mi.mesh.surface_get_material(i)
		if current == null:
			current = plain
		if current is BaseMaterial3D:
			_ghosted.append({"kind": "surface", "node": mi, "surface": i, "original": mi.get_surface_override_material(i)})
			mi.set_surface_override_material(i, _ghost_of(current as BaseMaterial3D, amount, cache))
		else:
			_hide(mi)
			return


## A part that cannot be dithered goes out of sight for as long as the cabinet is a ghost.
func _hide(node: Node3D) -> void:
	if node.visible:
		_ghosted.append({"kind": "hide", "node": node})
		node.visible = false


const _GHOST_CODE := """
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float keep = 0.35;
void fragment() {
	// Interleaved gradient noise: a fixed screen-space pattern, one pixel in `keep` survives. Flat
	// colour and no light or texture on purpose: held, the cabinet is a ghost, and a Quest pays for
	// every pixel of a 1.8 m box twice over in stereo.
	float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (n > keep) {
		discard;
	}
	ALBEDO = albedo.rgb;
}
"""

## The one shader every ghost copy shares.
static var _ghost_shader: Shader = null


func _ghost_of(src: BaseMaterial3D, amount: float, cache: Dictionary) -> ShaderMaterial:
	var ghost: ShaderMaterial = cache.get(src)
	if ghost != null:
		return ghost
	if _ghost_shader == null:
		_ghost_shader = Shader.new()
		_ghost_shader.code = _GHOST_CODE
	ghost = ShaderMaterial.new()
	ghost.shader = _ghost_shader
	ghost.set_shader_parameter("albedo", src.albedo_color)
	ghost.set_shader_parameter("keep", 1.0 - amount)
	cache[src] = ghost
	return ghost


## Lay the material ghost again when what moves with the cabinet is no longer what it was laid over.
## Nothing to do with the per-instance fade (no `_ghosted` then).
func _relay_ghost() -> void:
	if _ghosted.is_empty() or _ghost_roots().size() == _ghost_root_count:
		return
	_set_ghost_materials(0.0)
	_set_ghost_materials(HELD_TRANSPARENCY)


## How many things were dressed as ghosts (the machine, its bay, its board, its guns): when it differs
## from what moves with the cabinet now, the ghost is laid again.
var _ghost_root_count := 0

## What the ghost changed, to undo it: {kind (override|surface|hide|label|shadow), node, original, surface}.
var _ghosted: Array[Dictionary] = []

## The transparency the cabinet's body is at, for the tests.
func held_transparency() -> float:
	if not _ghosted.is_empty():
		return HELD_TRANSPARENCY
	var body := find_child("SideL", true, false) as GeometryInstance3D
	return body.transparency if body != null else 0.0


# ── door, saved as the lid angle ────────────────────────────────────────────

func get_lid_angle_deg() -> float:
	return _bay.get_open_deg() if _bay != null else -1.0


func set_lid_angle_deg(open_deg: float) -> void:
	if _bay != null:
		_bay.set_open_deg(open_deg)


func is_lid_open() -> bool:
	return _bay != null and _bay.is_open()


# ── the game's art ──────────────────────────────────────────────────────────

## The board (or cassette) went into the bay: dress the cabinet in its art (system.gd
## `_on_cartridge_inserted`, which every drop, restore and re-dock reaches).
func on_media_inserted(cart: Node) -> void:
	_strip_game()
	if cart == null or not cart.has_method("get_rom_path"):
		_request_form(_base_spec)
		return
	var art := ArcadeCabinetArt.for_rom(str(cart.get("systemid")), str(cart.call("get_rom_path")))
	# The generic cabinet follows the game: only a MAME-style romset has a profile (the Neo Geo,
	# Daphne and DICE cabinets keep their own panels).
	var profile: ArcadeGameProfile = null
	if ArcadeProfiles.is_arcade_system(str(cart.get("systemid"))):
		profile = ArcadeGameProfile.for_rom_path(str(cart.call("get_rom_path")))
	# The form first (it builds the slots the art hangs in and the panels the profile dresses).
	_request_form(form_for(profile))
	apply_art(art["wheel"] as Texture2D, art["cover"] as Texture2D)
	if profile != null:
		apply_game_profile(profile)
		_watch_descriptors = true
		_descriptor_wait = 0.0
		_ask_bezel(str(cart.call("get_rom_path")))


## The board left: the plain cabinet again, with its title, in its own form.
func on_media_cleared() -> void:
	_strip_game()
	_request_form(_base_spec)


func _strip_game() -> void:
	_art_wheel = null
	_art_cover = null
	_bezel_for = ""
	_bezel_texture = null
	_hang_bezel()
	_strip_art()
	_watch_descriptors = false
	apply_game_profile(null)


# ── the form follows the game ────────────────────────────────────────────────

## The row this cabinet was baked from (ArcadeCabinetSpecs.variants, named on the scene's root), or {} for a
## scene that names none (a mod's cabinet, an old bake): such a cabinet keeps the form it has.
var _base_spec: Dictionary = {}
## The spec the standing form was built from.
var _form_spec: Dictionary = {}
## Whether the cabinet takes the shape of the game in its bay. Always, for a player: it is a seam for the tests
## and the probes, which keep a cabinet's own form to look at what the profile alone hides.
var _morph_enabled := true
## A form asked for while a core runs on this one: built when the machine goes off.
var _pending_form: Variant = null


## The spec this cabinet takes for a game (ArcadeCabinetSpecs.for_game), or its own row when it does not
## follow the game (no row, following switched off by a test, no profile).
func form_for(profile: ArcadeGameProfile) -> Dictionary:
	if _base_spec.is_empty() or not _morph_enabled or profile == null:
		return _base_spec
	return ArcadeCabinetSpecs.for_game(_base_spec, profile)


## The spec the standing form was built from ({} for a cabinet that has no row), for the tests and the probe.
func form_spec() -> Dictionary:
	return _form_spec


## Turn following the game on or off (tests and probes); what is standing changes at once.
func set_morph_enabled(on: bool) -> void:
	if on == _morph_enabled:
		return
	_morph_enabled = on
	_request_form(form_for(_game))


func is_morph_enabled() -> bool:
	return _morph_enabled


## Ask for a form: built at the end of the frame, once (a board pulled and another seated in one frame builds
## one form), and never inside the callback that asked, which is often a snap zone handing over a board while
## the tree is busy with the nodes it moves.
func _request_form(spec: Dictionary) -> void:
	if spec.is_empty():
		return
	_pending_form = null
	var queued := _wanted_form != null
	_wanted_form = spec
	if not queued:
		_build_wanted_form.call_deferred()


## The form last asked for and not yet built, or null.
var _wanted_form: Variant = null


func _build_wanted_form() -> void:
	if _wanted_form == null:
		return
	var spec: Dictionary = _wanted_form
	_wanted_form = null
	var host := get_parent()
	if host != null and bool(host.get("is_powered_on")):
		# Never under a running core: its ports and the guns on them are in use. When it goes off.
		_pending_form = spec
		return
	morph_to(spec)


## Build the form `spec` asks for in place of the one standing (ArcadeCabinetBuilder.build_form): every part a
## form owns is taken away and built again, the modules are found again, and what hangs on them (the input,
## the guns and their cords, the port zones, the collision and pointer boxes, the art, the profile) is wired
## to the new ones. Nothing happens when the spec builds what is standing.
func morph_to(spec: Dictionary) -> void:
	if spec.is_empty() or (not _form_spec.is_empty() and ArcadeCabinetSpecs._same_form(spec, _form_spec)):
		return
	var host := get_parent()
	for c in _controls:
		if is_instance_valid(c):
			c.set_attached(false)
	var ghost := _ghost_on
	if ghost:
		_set_transparency(0.0)
	if host != null and host.has_method("before_cabinet_form"):
		host.call("before_cabinet_form")
	for child in get_children():
		if child.has_meta(ArcadeCabinetBuilder.FORM_META):
			remove_child(child)
			child.queue_free()
	ArcadeCabinetBuilder.new(spec, self).build_form()
	_form_spec = spec
	_collect_modules()
	_wire_stage_seats()
	ArcadeShadowBudget.trim(self)
	_light_marquee(_lit)
	_strip_art()
	_hang_art()
	_hang_bezel()
	for c in _controls:
		c.apply_profile(_game)
	for door in _coins:
		door.set_door_enabled(_game == null or door.player < _game.coin_doors())
	if host != null and host.has_method("after_cabinet_form"):
		host.call("after_cabinet_form")
	if _input != null:
		_input.rewire(_controls, _coins, _pedals.duplicate())
	_refresh_ground_placement()
	if ghost:
		_set_transparency(HELD_TRANSPARENCY)
	form_changed.emit()


## The cabinet's form was built again (morph_to): for the probe, the tests and whatever hangs on its parts.
signal form_changed


## A dancer's standing seat (ArcadeCabinetBuilder._build_stage_seat, `StageSeat<n>`, one a square, the squares in the order of the players): while the
## player stands up on the platform their own controller plays that player (the panel is attached, so the keys, the pad and a headset's sticks press
## the arrows), and when they step down it does not. The seats are the form's own and go with it: freed with the player on one, it lets them down.
func _wire_stage_seats() -> void:
	for i in _controls.size():
		var seat := find_child("StageSeat%d" % (i + 1), true, false) as CockpitSeat
		if seat != null:
			seat.seated_changed.connect(_on_stage_seat.bind(i))


func _on_stage_seat(on: bool, index: int) -> void:
	if index < _controls.size() and is_instance_valid(_controls[index]):
		_controls[index].set_attached(on)


## Is a player standing up on dancer `index`'s platform?
func stage_seat_occupied(index: int) -> bool:
	var seat := find_child("StageSeat%d" % (index + 1), true, false) as CockpitSeat
	return seat != null and seat.is_occupied()


# ── the game's needs ────────────────────────────────────────────────────────

## How often, while the machine runs, to ask the core whether it has described its inputs yet.
const DESCRIPTOR_POLL := 0.5

var _game: ArcadeGameProfile = null
var _watch_descriptors := false
var _descriptor_wait := 0.0


## The profile the cabinet is dressed for, or null when it shows the whole panel.
func game_profile() -> ArcadeGameProfile:
	return _game


## Show what this game uses and no more (ArcadeGameProfile): each panel, its stick and caps and the
## words on them, and the coin doors. Null puts everything back. Only what is DRAWN follows the
## game; the input is never filtered, so a cap hidden by a wrong guess still plays from a
## controller or the keyboard.
func apply_game_profile(profile: ArcadeGameProfile) -> void:
	_game = profile
	for c in _controls:
		c.apply_profile(profile)
	for door in _coins:
		door.set_door_enabled(profile == null or door.player < profile.coin_doors())
	# The TEST and SERVICE switches are there when MAME says the game reads one (or nothing is known of it).
	for service in _services:
		service.set_enabled(profile == null or not profile.known or profile.has_service())


## A TEST or SERVICE switch was pressed in the compartment: the machine presses what the core calls it.
func _on_service_pressed(which: StringName) -> void:
	var host := get_parent()
	if host != null and host.has_method("press_core_service"):
		host.call("press_core_service", which)


## Ask the running core for its descriptors; the first answer settles it (they arrive during load).
func _poll_descriptors() -> void:
	var sys := get_parent()
	if _game == null or sys == null or not bool(sys.get("is_powered_on")) or not sys.has_method("get_libretro_node"):
		return
	var lib := sys.call("get_libretro_node") as Libretro
	if lib == null:
		return
	var described: Array = lib.GetInputDescriptors()
	if described.is_empty():
		return
	_watch_descriptors = false
	_game.apply_descriptors(described)
	apply_game_profile(_game)


func _strip_art() -> void:
	for slot in [_art_marquee] + _art_sides:
		if slot != null:
			slot.visible = false
			slot.material_override = null
	_art_marquee_mat = null
	if _marquee_title != null:
		_marquee_title.visible = true


## The System tab's toggle: the art comes off (or goes back on) at once, the game staying in the bay.
func set_art_enabled(on: bool) -> void:
	if on == _art_enabled:
		return
	_art_enabled = on
	_strip_art()
	if on:
		_hang_art()
	_hang_bezel()


# ── the game's bezel ────────────────────────────────────────────────────────

## The game's own bezel round the tube (ArcadeBezel: the player's MAME artwork), or null; and where the screen is
## in it. Loaded off the main thread when the board goes in.
var _bezel_texture: Texture2D = null
var _bezel_hole := Rect2()
## The ROM the bezel was asked for: an answer for a board pulled since is dropped.
var _bezel_for := ""


func _ask_bezel(rom_path: String) -> void:
	_bezel_for = rom_path
	ArcadeBezel.load_for_rom_async(rom_path, RetroSystemModelArcadeCabinet._bezel_arrived.bind(get_instance_id(), rom_path))


## The loader's answer, on the main thread. Static and by id: the cabinet may be gone by the time it lands.
static func _bezel_arrived(found: Dictionary, cabinet_id: int, rom_path: String) -> void:
	var cabinet := instance_from_id(cabinet_id) as RetroSystemModelArcadeCabinet
	if cabinet != null and is_instance_valid(cabinet):
		cabinet.apply_bezel(found, rom_path)


## Hang what ArcadeBezel found for `rom_path` ({} for nothing), if that is still the board in the bay.
func apply_bezel(found: Dictionary, rom_path: String) -> void:
	if rom_path != _bezel_for:
		return
	_bezel_texture = null
	if not found.is_empty() and found.get("image") is Image:
		_bezel_texture = ImageTexture.create_from_image(found["image"] as Image)
		_bezel_hole = found["hole"]
		print("[ArcadeCabinet] bezel for %s from the %s artwork%s" % [rom_path.get_file(), str(found.get("set", "")),
			(" (" + str(found.get("credit", "")).get_slice("\n", 0).strip_edges() + ")") if not str(found.get("credit", "")).is_empty() else ""])
	_hang_bezel()


## The bezel on the tube while the art is on and there is one; the plain black frame otherwise.
func _hang_bezel() -> void:
	if _screen != null:
		_screen.set_bezel(_bezel_texture if _art_enabled else null, _bezel_hole)


## The bezel hanging on the tube now, or null (the tests).
func bezel_texture() -> Texture2D:
	return _bezel_texture


func is_art_enabled() -> bool:
	return _art_enabled


## Hang the pictures: the marquee shows the wheel, else the cover, else keeps its title; the sides
## show the cover. Each fits its slot at its own proportions.
func apply_art(wheel: Texture2D, cover: Texture2D) -> void:
	_art_wheel = wheel
	_art_cover = cover
	_strip_art()
	_hang_art()


func _hang_art() -> void:
	if not _art_enabled:
		return
	var wheel := _art_wheel
	var cover := _art_cover
	var marquee_tex: Texture2D = wheel if wheel != null else cover
	if _art_marquee != null and marquee_tex != null:
		_art_marquee_mat = _art_material(marquee_tex, wheel != null)
		_art_marquee_mat.emission_enabled = _lit
		_art_marquee_mat.emission_texture = marquee_tex
		_art_marquee_mat.emission_energy_multiplier = 0.9
		_hang(_art_marquee, marquee_tex, _art_marquee_mat)
		if _marquee_title != null:
			_marquee_title.visible = false
	if cover != null:
		for side in _art_sides:
			_fill(side, cover, _art_material(cover, false))


## A side's art fills the whole flank (its mesh is the silhouette, UV 0..1) and the picture is cropped to
## the flank's proportions, centred: what does not fit is cut, never stretched.
func _fill(slot: MeshInstance3D, tex: Texture2D, mat: StandardMaterial3D) -> void:
	var flank: float = slot.get_meta("aspect", 1.0)
	var size := tex.get_size()
	var pic := size.x / maxf(size.y, 1.0)
	var keep := Vector2.ONE
	if pic > flank:
		keep.x = flank / pic
	else:
		keep.y = pic / flank
	mat.uv1_scale = Vector3(keep.x, keep.y, 1.0)
	mat.uv1_offset = Vector3((1.0 - keep.x) * 0.5, (1.0 - keep.y) * 0.5, 0.0)
	slot.material_override = mat
	slot.visible = true


func _hang(slot: MeshInstance3D, tex: Texture2D, mat: StandardMaterial3D) -> void:
	var box: Vector2 = slot.get_meta("box", Vector2.ONE)
	var size := ArcadeCabinetArt.fit(tex.get_size(), box)
	slot.scale = Vector3(size.x, size.y, 1.0)
	slot.material_override = mat
	slot.visible = true


## A StandardMaterial3D, never a ShaderMaterial: a held cabinet dithers BaseMaterial3Ds and HIDES the
## rest (`_set_ghost_materials`). A wheel has alpha, a cover does not.
func _art_material(tex: Texture2D, alpha: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


# ── power ───────────────────────────────────────────────────────────────────

func on_power_on() -> void:
	_light_marquee(true)
	_watch_descriptors = _game != null
	_descriptor_wait = 0.0
	# A dancer who stood up on the platform before the machine was on: a panel attached to a machine that is off lets go, so it is taken again now.
	for i in _controls.size():
		if stage_seat_occupied(i) and is_instance_valid(_controls[i]):
			_controls[i].set_attached(true)


func on_power_off() -> void:
	_light_marquee(false)
	if _pending_form != null:
		var spec: Dictionary = _pending_form
		_pending_form = null
		_request_form(spec)
	# The core's words are about the run that just ended; the table alone stands.
	if _game != null and _game.is_described():
		_game.clear_descriptors()
		apply_game_profile(_game)
	_watch_descriptors = false


func _light_marquee(on: bool) -> void:
	_lit = on
	if _art_marquee_mat != null:
		_art_marquee_mat.emission_enabled = on
	if _marquee_mat == null:
		return
	_marquee_mat.emission_enabled = on
	_marquee_mat.emission_energy_multiplier = 0.9 if on else 0.0
