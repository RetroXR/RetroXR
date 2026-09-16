## RetroSystemModelPCTower — a beige 90s mini-tower PC, the ScummVM "console".
##
## Primitive geometry authored in pc_tower.tscn, deliberately: this exists first to
## prove the SLIDING optical tray, and a box tower takes primitives well (a painted
## steel case is flat panels and square corners, the same reasoning the room's desk
## and wardrobe use). A detailed shell can replace the geometry later without
## touching any of the wiring here.
##
## The tray is the point. Every other disc system in RetroXR is a lidded well —
## MediaTray swings `lid_pivot` about its local X and the disc either stays on the
## spindle or rides a flip-open door. A PC CD-ROM does neither: the tray TRANSLATES
## out of the bay, carrying the disc with it.
##
## That needs no change to MediaTray, because RetroSystem hands lid animation to
## bespoke models via play_open/play_close and only asks the model for
## get_disc_lid_pivot() so the seated disc can be reparented to the moving part.
## So MediaTray keeps owning the gating, seating, spin and collision, and this
## script owns the motion — which happens to be a slide.
class_name RetroSystemModelPCTower
extends RetroSystemModel


## How far the tray travels out of the bay, along the tower's local +Z (the front).
##
## 145 mm, not 135: at 135 the disc's REAR edge still sat 15 mm inside the case
## front once the tray was out, so a disc laid on the tray clipped through the
## bezel. It now clears by 9.5 mm.
@export var tray_travel: float = 0.145
@export var tray_time: float = 0.9

## A/V socket spacing and how far their zones stand off the back panel — see
## configure_av_ports().
const AV_PORT_PITCH := 0.018
const AV_PORT_PROUD := 0.010

@onready var _tray_pivot: Node3D = $TrayPivot
@onready var _led: MeshInstance3D = $Front/PowerLed
@onready var _drive_led: MeshInstance3D = $Front/DriveLed

var _tray_rest: Vector3 = Vector3.ZERO
var _tray_tween: Tween = null


## Back-panel label node -> the TransportGlyphs key it prints.
const PORT_GLYPHS := {
	"MouseLabel": "mouse",
	"KeyboardLabel": "keyboard",
	"VgaLabel": "vga",
	"SpeakerLabel": "speakers",
	"GameLabel": "gamepad",
}

## 6 mm, against the 5 mm of text it replaces. A glyph carries a whole word in one
## character and wants to be bigger than the word was — but only just: keyboard
## socket to VGA flange is 8.2 mm and the icon has to sit between them.
##
## Rastered at 48 and scaled down, not asked for at 6. font_size is the size the
## glyphs are BUILT at, so asking for 6 makes a six-pixel-tall atlas and magnifies
## it into a smear; see the note in pc_tower.tscn.
const PORT_GLYPH_M := 0.006
const PORT_GLYPH_RASTER := 48


func _ready() -> void:
	_tray_rest = _tray_pivot.position
	_label_ports()
	_set_led(_led, false, Color(0.25, 0.85, 0.35))
	_set_led(_drive_led, false, Color(1.0, 0.7, 0.2))


## Print an icon over each socket instead of its name.
##
## Done here rather than in the scene because a .tscn cannot chain the symbol font,
## and the Nerd Font codepoints are private-use: without TransportGlyphs.font()
## putting that font behind the project default, every one renders as tofu. The
## scene keeps the words it had, so the panel still reads in the editor and still
## says something if this never runs — the same arrangement label_buttons() uses on
## the decks' ButtonLabels.
func _label_ports() -> void:
	for node_name: String in PORT_GLYPHS:
		var lbl := get_node_or_null("Back/%s" % node_name) as Label3D
		if lbl == null:
			continue
		lbl.font = TransportGlyphs.font()
		lbl.font_size = PORT_GLYPH_RASTER
		lbl.pixel_size = PORT_GLYPH_M / float(PORT_GLYPH_RASTER)
		lbl.text = TransportGlyphs.glyph(str(PORT_GLYPHS[node_name]))


# --- ports ------------------------------------------------------------------

func configure_controller_ports(port_zones: Array) -> void:
	# Authored PortSeat markers win over any computed pose — the same
	# "authored beats computed" idiom as DiscSeat.
	for i in range(port_zones.size()):
		var zone := port_zones[i] as Node3D
		if zone == null:
			continue
		var seat := find_child("PortSeat%d" % (i + 1), true, false) as Node3D
		if seat != null:
			zone.global_transform = seat.global_transform
	# system.tscn's grey port box and floating number are stand-ins for the default
	# procedural shell. Seats 1 and 2 mould their own colour-coded PS/2 sockets, so
	# leaving the stand-in on would park a grey cube and a "1" over the purple one.
	#
	# The game port keeps its recess: it has no moulded socket of its own, and the
	# plain dark rectangle is what a controller port looks like everywhere else in
	# the project. Its NUMBER still goes, though — the seat is rotated 180 about X
	# so the socket faces out of the back, and that flips Y, which stands a Label3D
	# on its head and drops it below the port instead of above. The panel names this
	# one in silkscreen (GameLabel) like every other socket on it.
	for i in range(port_zones.size()):
		var zone := port_zones[i] as Node3D
		if zone == null:
			continue
		var lbl := zone.get_node_or_null("PortLabel") as Label3D
		if lbl != null:
			lbl.hide()
		var recess := zone.get_node_or_null("PortRecess") as MeshInstance3D
		if recess != null and i != 2:
			recess.hide()


# --- the sliding tray -------------------------------------------------------

## Where a seated disc should be parented so it rides out with the tray.
func get_disc_lid_pivot() -> Node3D:
	return _tray_pivot


func play_open() -> void:
	_slide_to(_tray_rest + Vector3(0.0, 0.0, tray_travel))


func play_close() -> void:
	_slide_to(_tray_rest)


func _slide_to(target: Vector3) -> void:
	if _tray_tween != null and _tray_tween.is_valid():
		_tray_tween.kill()
	# Real trays ease out and thump home rather than moving linearly.
	_tray_tween = create_tween()
	_tray_tween.tween_property(_tray_pivot, "position", target, tray_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## The shelf carries the disc out with it, so the drive cannot have caught while
## it is moving.
func is_tray_moving() -> bool:
	return _tray_tween != null and _tray_tween.is_valid() and _tray_tween.is_running()


# --- hardware description ---------------------------------------------------

## A PC takes keyboard and mouse rather than joypads, but RetroSystem's ports are
## how any input reaches the core, so two are kept — plus the game port, which is
## the one socket here a joypad really did go into.
##
## They stay ORDINARY controller ports: RetroKeyboard and RetroMouse already
## implement the port contract (on_plugged_in / on_unplugged) and spawn the same
## cable a gamepad does. Only the socket geometry and its PC99 colour coding —
## purple keyboard, green mouse, matching the plug meshes — say otherwise.
##
## Seat 3 is the game port. A pad in it drives libretro port 0 whichever cabinet
## slot it occupies, exactly as the mouse does — see RetroSystem._libretro_port_for.
## SystemInfo.native_ports OVERRIDES this number whenever it is set, so the count
## here is only half the story: every computer .tres has to allow three too.
func get_controller_port_count() -> int:
	return 3


## Seat 3 — the 15-pin socket down with the audio jacks. Seats 1 and 2 are the
## PS/2 keyboard and mouse, which drive their own ports.
func game_port_index() -> int:
	return 2


## Saves live on the hard disk, not a removable card.
func card_slot_count() -> int:
	return 0


func is_handheld() -> bool:
	return false


# POWER on the front bezel; the tray's own EJECT button beside the bay. No reset —
# a 90s tower's reset was a recessed pinhole, not something to press in VR.
#
# Both sit in the bezel and so travel INTO it, along the tower's -Z. VRButton
# defaults to -Y, which is right for a button on a top face and wrong for one
# facing you: it sinks the cap down through the bezel instead of into it. The
# axis is set in local space rather than from global_transform — every frame
# between these buttons and the model is identity, and a local write does not
# care whether the tower has been placed in the room yet.
func configure_buttons(power_btn: VRButton, reset_btn: VRButton, eject_btn: VRButton) -> void:
	if power_btn != null:
		power_btn.position = $Front/PowerButtonAnchor.position
		power_btn.depress_depth = 0.003
		power_btn.depress_axis = Vector3(0, 0, -1)
		var pl := power_btn.get_node_or_null("ButtonLabel") as Label3D
		if pl != null:
			pl.hide()
	if eject_btn != null:
		eject_btn.position = $Front/EjectButtonAnchor.position
		eject_btn.depress_depth = 0.003
		eject_btn.depress_axis = Vector3(0, 0, -1)
		var el := eject_btn.get_node_or_null("ButtonLabel") as Label3D
		if el != null:
			el.hide()
	if reset_btn != null:
		reset_btn.set_active(false)


## This tower has two drives, and which one a machine loads from is a property of
## the MACHINE, not of the shell: scummvm's games are on CD and go in the optical
## tray, and the other seventeen platforms wearing this tower load from a 3.5 in
## floppy and go in the drive below it.
##
## Seating a floppy system's media in the tray is what put it INSIDE the tower: at
## rest the tray is drawn back into the case, so a cartridge snapped to DiscSeat is
## swallowed by the beige box with nothing to grab. Only a disc system opens that
## tray, which is what makes the well reachable.
##
## The disc case: DiscSeat's position is local to TrayPivot, NOT to the model root,
## and `slot` lives in the model root's frame. Assigning it raw put the well at the
## tower's base 6 mm under the floor — 36 cm from the tray — so a disc had nothing
## to snap to however far the tray slid out. Compose the pivot's own transform in.
## Its pose is then read back by RetroSystem and re-expressed relative to
## get_disc_lid_pivot(), so it must be set with the tray at its REST pose — which it
## is, since _ready has not moved it.
func configure_cartridge_slot(slot: Node3D) -> void:
	if MediaDimensions.is_disc_system(_host_systemid()):
		var pivot: Node3D = $TrayPivot
		slot.position = pivot.transform * (pivot.get_node("DiscSeat") as Node3D).position
	else:
		# Authored, like every other seat on this model — see FloppySeat's note in
		# pc_tower.tscn for the basis and the 40 mm bite. Front is a bare Node3D at
		# the model root, so the marker's local transform is already in `slot`'s
		# frame; give Front a transform and this silently breaks.
		slot.transform = ($Front/FloppySeat as Node3D).transform
	var v := slot.get_node_or_null("SlotVisual") as MeshInstance3D
	if v != null:
		v.visible = false


## The systemid of the machine wearing this tower, or "" before it is parented.
## The tower is one shell across eighteen platforms, so anything that differs
## between them has to be asked of the host rather than baked into the model.
func _host_systemid() -> String:
	var host := get_parent()
	if host == null:
		return ""
	var id: Variant = host.get("systemid")
	return str(id) if id is String else ""


## Composite out, the same three sockets the primitive system carries. A tower's
## picture and sound leave on a card at the back, so the player runs a lead from
## here to the set rather than the console arriving with one attached — declaring
## the channels is all it takes, since RetroSystem builds sockets INSTEAD of a
## captive cable for any model that answers this.
func av_port_channels() -> Array:
	return [RcaPort.Channel.VIDEO, RcaPort.Channel.AUDIO_L, RcaPort.Channel.AUDIO_R]


## Laid across the back panel on 18 mm centres — the spacing the primitive, the NES
## and the decks all use — centred on AvAnchor, which is where the captive lead
## used to leave the case: low on the panel and well clear of the PS/2 stack above.
##
## Two conventions, both borrowed rather than derived:
##   * 10 mm PROUD of the panel. rca_port.tscn puts the zone where a seated plug's
##     origin belongs and pushes the jack back by that much so its flange lands on
##     the panel — copy a port's transform and the plug still seats right.
##   * Rotated 180 about X, so each socket's local +Z faces out of the back. That
##     is the same correction PortSeat1/2 carry a few lines above in the scene, and
##     for the same measured reason: a zone at identity yields a plug at
##     diag(1,-1,-1), barrel buried in the case.
##
## Local, like the rest of this model's placement: Back is a bare Node3D at the
## model root and the ports are children of the system, which share that frame.
func configure_av_ports(ports: Array) -> void:
	var anchor: Vector3 = ($Back/AvAnchor as Node3D).position
	var span: float = AV_PORT_PITCH * float(ports.size() - 1)
	for i in ports.size():
		var port: Node3D = ports[i]
		port.position = Vector3(
			anchor.x - span * 0.5 + AV_PORT_PITCH * float(i),
			anchor.y,
			anchor.z - AV_PORT_PROUD)
		port.rotation = Vector3(PI, 0.0, 0.0)


## AvAnchor sits at z = -0.222, 2 mm off the case's back face at -0.22 — it was
## placed for a captive lead, which leaves from a point rather than seating on a
## surface. The legend IS a surface, so it backs off by 11.5 mm instead of the
## standard 9.5 and lands at -0.2205: half a millimetre proud of the panel, the same
## standoff the PS/2 silkscreen above it carries.
func configure_av_legend(legend: AvLegend) -> void:
	legend.standoff = AV_PORT_PROUD + 0.0015
	legend.rebuild()


## Ports onto the BACK panel, where a PC's keyboard and mouse actually plug in.
## Left at their defaults they sat at the tower's base and dipped 6 mm below the
## floor, since the default layout assumes a console lying flat.
## Safe to read the marker's position raw, unlike DiscSeat above: Front and Back
## are bare Node3Ds at the model root, so their children's local positions ARE
## model-root-relative. Give either of them a transform and this silently breaks.
func configure_cable_attach(attach_point: Node3D) -> void:
	attach_point.position = $Back/AvAnchor.position
	var v := attach_point.get_node_or_null("PortVisual") as MeshInstance3D
	if v != null:
		v.visible = false


func configure_collision(host: Node3D) -> void:
	# The case only. The tray is excluded on purpose: it moves, and a collider
	# that slides out of the body would shove whatever is in front of the tower.
	var box := Vector3(0.19, 0.42, 0.44)
	var pos := Vector3(0.0, 0.21, 0.0)
	for path in ["CollisionShape3D", "PointerArea/CollisionShape3D"]:
		var col := host.get_node_or_null(path) as CollisionShape3D
		if col != null and col.shape is BoxShape3D:
			col.shape = col.shape.duplicate()
			(col.shape as BoxShape3D).size = box
			col.position = pos


func on_power_on() -> void:
	_set_led(_led, true, Color(0.25, 0.85, 0.35))
	_set_led(_drive_led, true, Color(1.0, 0.7, 0.2))


func on_power_off() -> void:
	_set_led(_led, false, Color(0.25, 0.85, 0.35))
	_set_led(_drive_led, false, Color(1.0, 0.7, 0.2))


func _set_led(led: MeshInstance3D, on: bool, tint: Color) -> void:
	if led == null:
		return
	var mat := led.get_surface_override_material(0) as StandardMaterial3D
	if mat == null or not mat.resource_local_to_scene:
		mat = StandardMaterial3D.new()
		mat.resource_local_to_scene = true
		led.set_surface_override_material(0, mat)
	mat.albedo_color = tint if on else tint.darkened(0.78)
	mat.emission_enabled = on
	mat.emission = tint
	mat.emission_energy_multiplier = 2.2 if on else 0.0
