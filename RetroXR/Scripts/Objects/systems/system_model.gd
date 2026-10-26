## RetroSystemModel — base class for system-specific console visual models.
##
## Subclasses load the appropriate GLB for their hardware and override the
## virtual methods below.  All overrides are optional stubs today; they will
## grow as physical animations, power lights, and port visuals are added.
##
## Hook naming. The read-only hooks come in two spellings: the older ones are
## get_-prefixed (get_controller_port_count, get_usb_port_count,
## get_lid_angle_deg, get_rf_channel, get_builtin_screen, ...), the newer ones a
## bare noun (card_slot_count, slot_insert_depth, power_slider, game_port_index,
## builtin_ethernet_port, ...). Both are FROZEN: every hook is overridden BY NAME
## in system_models/*.gd and in installed mod packs, and GDScript has no
## `override` keyword, so a renamed hook leaves every override a new method that
## is never called, silently. Copy a hook's exact name from this file when
## overriding it; give a NEW hook the bare-noun form.
class_name RetroSystemModel
extends Node3D

## Cache for has_baked_shell(). Lazy rather than resolved in _ready(): subclasses
## ask this DURING their own _ready(), and not all of them chain to a base one.
var _baked_shell: Node3D = null
var _baked_shell_checked: bool = false


# ── The machine's own picture ─────────────────────────────────────────────────
#
# A model owns the panels it authored, so a model paints them — nobody else. The
# C++ video handler used to install a material on whichever mesh it was handed,
# and every model here then read the texture back out of that material to wrap it
# in an LCD or stereo shader of its own. The picture is asked for now.


## The core's picture, from the machine this model belongs to. Null when nothing
## is running. A different object after a resolution change, so it is read per
## frame rather than cached.
func host_picture() -> Texture2D:
	var host := get_parent()
	if host == null or not host.has_method("get_video_texture"):
		return null
	return host.get_video_texture()


## True while a video-out cable has taken the picture to a television, which for
## a handheld means its own panel goes dark (Super Game Boy).
func host_picture_on_tv() -> bool:
	var host := get_parent()
	return host != null and host.has_method("picture_on_tv") and host.picture_on_tv()


## The material a panel shows a raw core picture in — emissive so it reads as lit
## from within, point-sampled so a 160-pixel-wide frame is not pre-softened before
## the headset resamples it. Moved here from VideoHandler::Init, which installed
## exactly this on whatever mesh it was given.
var _picture_material: StandardMaterial3D = null


func picture_material(tex: Texture2D) -> StandardMaterial3D:
	if _picture_material == null:
		_picture_material = StandardMaterial3D.new()
		_picture_material.albedo_color = Color(0, 0, 0, 1)
		_picture_material.emission_enabled = true
		_picture_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_picture_material.emission_texture = tex
	return _picture_material


## True when this model wears a detailed shell — a GLB instanced into the scene as
## a child named "Shell".
##
## This replaced an authored `primitive_shell` bool, which said the same thing and
## could disagree with the scene. It did: atari_lynx, neo_geo_pocket, pokemon_mini,
## supervision and wonderswan are plain authored models that never set it, so they
## were treated as detailed shells — their own printed legends were hidden and they
## got no nameplate, despite having no moulding to carry either. Asking the scene
## cannot drift.
func has_baked_shell() -> bool:
	if not _baked_shell_checked:
		_baked_shell_checked = true
		_baked_shell = get_node_or_null("Shell") as Node3D
	return _baked_shell != null


## True when this model supplies the console's body itself, so the cabinet should
## drop its procedural box — and, with it, the procedural disc tray or slot that
## box would otherwise grow.
##
## RetroSystem used to derive this from the model's REGISTRY ID: anything not
## called "placeholder" was assumed to bring geometry. That is the same trap
## has_baked_shell was written to escape, and it sprang the same way. A row can
## exist for reasons that have nothing to do with geometry — the Wii's exists to
## carry the core options its remote cannot work without — and such a model wears
## the procedural box like any other. Under the id rule it lost the box and the
## disc slot both, and spawned as a set of buttons and ports floating in mid-air.
##
## Asking the model cannot drift: a model that draws nothing says so.
func brings_own_body() -> bool:
	return true


## Become one of the colors this model's row lists (SystemModelRegistry
## `variants`), by its id. Called once, as the console builds its model and
## before it wires anything to it, and only for a console that names one: the
## model as it comes is asked nothing. An id the model does not know is one a
## save has outlived, and is left as the model's own color.
func apply_variant(_variant: String) -> void:
	pass


## Called when the system is powered on (e.g. light up power LED, play boot animation).
func on_power_on() -> void:
	if _power_slider != null:
		_power_slider.set_value_no_signal(1.0)


## Called when the system is powered off (e.g. extinguish power LED).
func on_power_off() -> void:
	if _power_slider != null:
		_power_slider.set_value_no_signal(0.0)


# --- power SLIDE switches ----------------------------------------------------
#
# Several consoles power on with a slide, not a push: the Genesis rocker travels
# left to ON, the N64's slides up. Driving those from the cabinet's generic
# VRButton made them sink into the case like a button, which is the wrong motion
# and hides the ON/OFF legend the shell prints either side of the cap.
#
# build_power_slider() replaces the button with a VRSlider mounted ON the shell's
# real cap, so the thing you grab is the thing that moves, and the two detents
# map to off/on. Subclasses that override on_power_on/on_power_off must call
# super() so an externally-driven power change (a save restore, a multiplayer
# event, the cartridge being pulled) still moves the switch.
var _power_slider: VRSlider = null

## Every power switch joins this, whether the base class built it (the console
## rockers below) or the model's scene authored it (HandheldModel). It is what
## tells ScenePersistence that a slider's position is a machine's STATE rather
## than a pose: a restored machine is always off, so a saved ON position brought
## a handheld back with its switch up and nothing running behind it.
const POWER_SWITCH_GROUP := "power_switch"


## Mount a two-detent power slider on `cap` and hide the generic push button.
## `axis` is the travel direction toward ON, in this model's local space;
## `throw` is the total travel in metres.
func build_power_slider(power_btn: VRButton, cap: MeshInstance3D,
		axis: Vector3, throw: float) -> VRSlider:
	if cap == null:
		return null
	if power_btn != null:
		power_btn.set_active(false)
	var slider := VRSlider.new()
	slider.name = "PowerSwitch"
	slider.axis_local = axis.normalized()
	slider.travel = throw
	slider.steps = 2
	slider.collision_layer = 1 | (1 << 20)
	var ab: AABB = cap.global_transform * cap.get_aabb()
	slider.engage_radius = clampf(maxf(ab.size.x, maxf(ab.size.y, ab.size.z)) * 0.9, 0.02, 0.05)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = ab.size + Vector3(0.006, 0.006, 0.006)
	col.shape = box
	slider.add_child(col)
	add_child(slider)                     # _ready() runs here, before adopting
	slider.global_position = ab.get_center()
	slider.set_knob_mesh(cap)
	slider.value_changed.connect(_on_power_slider_changed)
	slider.add_to_group(POWER_SWITCH_GROUP)
	_power_slider = slider
	return slider


func _on_power_slider_changed(v: float) -> void:
	var host := get_parent()
	if host == null or not host.has_method("toggle_power"):
		return
	# The replicated position is visual state; EV_SYS_POWER is the one semantic
	# action. Letting both paths toggle would turn a remote machine twice.
	if NetworkManager.is_event_applying():
		return
	if (v > 0.5) != bool(host.get("is_powered_on")):
		host.toggle_power()


## Play the cartridge/disc tray open animation (if supported).
func play_open() -> void:
	pass


## Play the cartridge/disc tray close animation (if supported).
func play_close() -> void:
	pass


## True while this model is driving its own tray between open and shut. Asked by
## RetroSystem._update_disc_spin, which will not turn a disc that is still on its
## way in.
##
## A SPRING-LATCHED lid leaves this false on purpose rather than by omission: that
## lid is shut by the player's hand and only reports once it is already home, so
## it is never in motion by the time the machine hears about it. Only a tray that
## moves UNDER THE BUTTON has a gap to cover.
func is_tray_moving() -> bool:
	return false


## True when this model's lid is a spring-loaded VRSpringLatchedHinge: the OPEN
## button only ever OPENS it (pressing it again while open does nothing — as on
## the real hardware, where the button is a latch release), and the lid is shut
## by hand, which reports back through RetroSystem.request_tray_state().
func has_spring_latched_lid() -> bool:
	return false


## Which controller socket is this machine's GAME PORT — the one a joystick went
## into, as opposed to the keyboard and mouse sockets beside it — or -1 for
## hardware that has no such distinction.
##
## Only computers need it. A console's pads drive the port they are plugged into;
## a DOS or Amiga core reads its one joystick on port 0 whatever socket the cabinet
## put it in, and RetroSystem._libretro_port_for uses this to pin exactly that one
## socket without touching the others (a C64 really does have two joystick ports).
func game_port_index() -> int:
	return -1


## How many USB-A sockets this hardware has, or -1 for its platform's
## (Connectors.USB_PORTS).
func get_usb_port_count() -> int:
	return -1


## Put the USB sockets on this model's shell. They arrive on the box's front face;
## a model with sockets of its own moves them onto those and hides each zone's
## UsbRecess, as configure_controller_ports does with the controller ports.
func configure_usb_ports(_usb_zones: Array) -> void:
	pass


## The connector this hardware's controller ports take, or "" for its platform's
## (Connectors.controller_port_of). Only a model whose ports are not its
## platform's own needs to say.
func get_controller_connector() -> String:
	return ""


## Returns the number of controller ports active on this hardware.
## The base system scene has 4 snap zones; ports beyond this count are hidden.
func get_controller_port_count() -> int:
	return 2


## Controller scenes this hardware is WIRED to, one per port in order, or [].
##
## A Famicom's two pads are moulded onto cords that come out of the back of the
## machine; there is no socket and nothing to unplug. Listing them here is what
## makes RetroSystem build them with the console, seat them, and lock those ports.
func captive_controllers() -> Array[String]:
	return []


## Where each of those pads rests, in this model's own frame -- a Famicom's two
## wells. One entry per captive controller; a short list leaves the rest where
## they spawn.
func captive_controller_rests() -> Array[Transform3D]:
	return []


## The path each of those cords takes while its pad is at rest, in this model's
## own frame, as a PackedVector3Array running from the pad's cable boss to the
## console's cord exit. One entry per captive controller; [] leaves every cord to
## the straight line VerletRope lays between its two anchors.
##
## Worth having because that straight line is wrong for exactly this case: a
## stowed pad sits a few centimetres from the hole its metre of cord leaves by,
## so the lay starts compressed several times over and the solver answers with
## standing arches rather than a cord. `length` is the rope's rest length, so a
## route can spend it.
func captive_cord_routes(_length: float) -> Array:
	return []


## How many removable card slots this SHELL has, or -1 for "no opinion, ask the
## system descriptor". Enables that many card snap zones.
##
## -1 rather than 0 is the whole point: a shell that has never thought about
## cards must not out-vote its console's descriptor, while a shell that returns 0
## is saying something stronger — this hardware has none, whatever the descriptor
## claims. Cartridge systems keep saves on the cartridge and mean the second one.
func card_slot_count() -> int:
	return -1


## True for handheld hardware (Game Boy family): the device has a built-in
## screen, is played while held, and its VR-controller input drives port 0.
func is_handheld() -> bool:
	return false


## The device's built-in display mesh (handhelds), or null. When no TV is
## connected the core renders here; plugging the video-out cable into a TV
## moves the picture there and unplugging brings it back.
func get_builtin_screen() -> MeshInstance3D:
	return null


## True if the core outputs a side-by-side stereo frame (left eye | right eye),
## i.e. the Virtual Boy. A connected TV then splits it per-eye like the eyepiece.
func is_stereo_side_by_side() -> bool:
	return false


## Video-out channels this hardware exposes. Single-output hardware (default)
## has one unlabelled channel showing the whole core frame, handled by the
## classic path (the C++ VideoHandler renders straight onto the connected TV).
## Multi-channel hardware (dual-screen handhelds) gets one cable PER channel;
## each connected TV then shows that channel's UV window of the composite
## framebuffer via the screen_window shader. Entry keys:
##   label     String  cable/port tag ("TOP"/"BOTTOM"); "" on single-channel
##   rect      Rect2   UV window into the composite framebuffer
##   touch     bool    taps on a TV showing this channel feed the touch screen
##   eye_shift float   right-eye UV-x shift for stereo SBS sources (0 = mono)
func get_video_channels() -> Array:
	return [{"label": "", "rect": Rect2(0, 0, 1, 1), "touch": false, "eye_shift": 0.0}]


## Handhelds normally hide the cabinet START/STOP button (they carry their own
## power switch). Dual-screen clamshells override this to keep the button —
## their hinge swallows the tiny back-edge knob, so a proper labelled button
## repositioned by configure_buttons() is the discoverable way to power them.
func has_start_stop_button() -> bool:
	return not is_handheld()


## Whether the cabinet's generic OPEN/EJECT button should appear on a system that
## has a disc loader. Override to false when the shell models its own release
## control and mounts a widget on it (the PSP's sprung OPEN latch), so the two
## don't both claim the same job — and the same mesh.
func has_eject_button() -> bool:
	return true


## Hide the generic grey port box and its number on every controller port.
##
## system.tscn ships those as stand-ins for the procedural default shell, which
## has no port geometry of its own. Any console whose GLB moulds real ports wants
## them gone — otherwise a grey cube and a floating "1" sit on top of the moulded
## socket. Call from configure_controller_ports.
static func hide_port_placeholders(port_zones: Array) -> void:
	for z: Node in port_zones:
		var recess := z.get_node_or_null("PortRecess") as MeshInstance3D
		if recess != null:
			recess.hide()
		var lbl := z.get_node_or_null("PortLabel") as Label3D
		if lbl != null:
			lbl.hide()


## Handhelds: create and wire the on-device controls (volume slider, power
## switch) against the owning RetroSystem. Called after the model loads.
func configure_handheld_controls(_host: Node3D) -> void:
	pass


## Interior open angle of a clamshell handheld's lid in degrees (0 = folded
## shut … 180 = flat open), or -1 for hardware without a lid. Read by
## ScenePersistence to save the lid pose; the -1 sentinel is the same
## "capability absent" convention as get_builtin_screen() → null.
func get_lid_angle_deg() -> float:
	return -1.0


## Restore a clamshell lid's interior open angle (0 shut … 180 flat). Hardware
## without a lid ignores it.
func set_lid_angle_deg(_open_deg: float) -> void:
	pass


## Whether the lid this model just posed counts as OPEN — the machine's own
## question, not the mesh's. RetroSystem asks it after restoring a saved angle,
## because the pose alone tells nobody whether the bay should be accepting media.
##
## The default reads the reported angle, which is right for anything that keeps
## no separate open/shut state; a model that has one (the PlayStation lid)
## overrides this so its own half-way rule stays the only rule.
##
## Only asked of a LOADER_TRAY console, so a cartridge flap never reaches here.
func is_lid_open() -> bool:
	return get_lid_angle_deg() > 0.0


## Reposition one memory-card snap zone onto the model's physical card slot.
## `index` is the slot, 0-based, in the same order card_slot_count() counts them.
##
## Called only for slots this model actually has, and called LAST in the slot
## setup, so a shell whose slots sit behind a door can shut them again here.
func configure_memory_card_slot(_slot: Node3D, _index: int) -> void:
	pass


## Core options this hardware REQUIRES (key -> value), merged into the core's
## .opt file before every content start. Used when a model only works with a
## specific core configuration (e.g. Virtual Boy forces vb_3dmode =
## side-by-side so the stereo eyepiece shader gets both eyes).
func get_forced_core_options() -> Dictionary:
	return {}


## RETRO_JOYPAD bits this hardware has no physical control for, as a mask.
## Cleared from the port state before it reaches the core, whatever bound them:
## a core is free to hang a hotkey off a button the machine never had, and the
## player has no way to know they are pressing it.
func get_unsupported_button_mask() -> int:
	return 0


## Emitted by a model whose bay only connects when its tray is pushed down (the
## NES ZIF cradle). `down` true = the cart is home and the machine may read it;
## false = the tray is up and the cart is merely lying in it.
@warning_ignore("unused_signal")
signal cart_tray_changed(down: bool)


## True when this model's bay defers the insert to a push, so RetroSystem knows the
## snap zone's own capture is not the moment the cart went in.
func has_push_tray() -> bool:
	return false


## For a push-tray bay: is the tray currently pushed home?
func is_tray_down() -> bool:
	return false


## Animate a controller plug into a port.  Called after XRTools has snapped and
## frozen the plug at the socket, on the same terms as play_cartridge_insert: the
## model tweens it from wherever the zone stood its ghost, then refreezes.
func play_port_plug_insert(_plug: Node3D, _zone: Node3D) -> void:
	pass


## Animate a cartridge into its slot.  Called after XRTools has snapped and
## frozen the cartridge at the slot position.  Subclasses unfreeze, tween from
## a system-specific start offset to the final position, then refreeze.
func play_cartridge_insert(_cartridge: Node3D, _slot: Node3D) -> void:
	pass


## Reposition the system's existing VRButton nodes to match the model's physical
## button locations and wire them to the GLB button meshes for depress animation.
## The existing signal connections to toggle_power/reset/eject are preserved — only
## the position and mesh reference are updated. eject_btn is the OPEN/eject button
## (disc consoles); models without a disc button ignore it.
func configure_buttons(_power_btn: VRButton, _reset_btn: VRButton, _eject_btn: VRButton) -> void:
	pass


## Reposition the SYNC button, on the consoles that pair wireless pads. Called from
## _setup_wireless_pads, after configure_buttons, and only when this hardware has
## one — which today means the Wii alone.
##
## Separate from configure_buttons because the cabinet builds this button on a
## different test (WiiLink.handles) and later in the sequence; a model that grows its
## own geometry must place it or it stays wherever system.tscn parked it, which on
## anything but the procedural box is mid-air.
func configure_sync_button(_sync_btn: VRButton) -> void:
	pass


## Reposition controller port snap zones to the model's physical port locations.
## port_zones is the system's Array of XRToolsSnapZone nodes (index 0 = port 1).
## Only move the zones the model has markers for; others keep their default positions.
func configure_controller_ports(_port_zones: Array) -> void:
	pass


## Reposition the cable attach point to the model's physical video-out port.
func configure_cable_attach(_attach_point: Node3D) -> void:
	pass


## The A/V SOCKETS this hardware wears, as RcaPort.Channel values in build order,
## or [] for hardware that keeps a captive lead.
##
## A console that lists sockets gets no cable of its own: RetroSystem builds these
## instead and the player runs a spawned lead to the set, which is what the
## hardware actually made you do. The list is what says whether it is stereo —
## [VIDEO, AUDIO_L, AUDIO_R] for most consoles, [VIDEO, AUDIO_L] for mono hardware
## like the NES, whose single audio cord then feeds both of the set's speakers.
##
## Handhelds are deliberately not in this world: their screen is their own, and the
## video-out lead is an extra rather than the only way to see anything.
func av_port_channels() -> Array:
	return []


func uses_av_ports() -> bool:
	return not av_port_channels().is_empty()


## True when every channel above leaves through ONE socket rather than one each.
##
## Orthogonal to av_port_channels on purpose: the Wii outputs the same three signals
## as any other stereo console — which is what decides whether its sound is stereo and
## which speaker each cord feeds — it just packages them in a single AV Multi Out
## shell. Folding that into the channel list would have made "what this machine puts
## out" and "how many holes it has" the same question, and they are not.
##
## The socket built is a MultiAvPort, whose channel_for(cord) is what tells the three
## cords apart once they are all in it. Which one is av_multi_port_scene's business.
func av_ports_are_multi_way() -> bool:
	return false


## WHICH multi-way socket, for a machine that says true above.
##
## Asked of the model rather than fixed in the cabinet because the shell is shared and
## the pinout is not. Nintendo put the same 12-pin Multi Out on the SNES, the N64, the
## GameCube and the Wii; the first three take one another's leads and the Wii takes
## none of them. A single socket scene would have let a Wii cable carry an N64's
## picture, which is a thing the hardware refuses.
##
## Empty means "use the cabinet's fallback", which keeps a model that claims multi-way
## and forgets this from losing its picture in silence.
func av_multi_port_scene() -> String:
	return ""


## Which channel this machine's RF modulator puts it on, or -1 for "no such switch".
##
## Only hardware old enough to reach a set through an RF switch has one — the NES
## wears a CH3/CH4 slide on its rear panel — and a television on its aerial input
## only shows a console whose channel matches its own tuning. -1 means the machine
## has no opinion, and RetroTV treats that as a match rather than as a mismatch, so
## anything else fed through an RF switch simply appears.
func get_rf_channel() -> int:
	return -1


## The channels that switch can be set to, in the order it slides, or [] for none.
## Read by the machine's menu, which offers the switch as a row.
func rf_channel_options() -> Array:
	return []


## Set the RF switch from somewhere other than a hand on it (the machine's menu).
## A model with a switch MOVES it, so the knob, the sound and the set's re-read all
## follow the one path a hand takes. Default: no switch, nothing to do.
func set_rf_channel(_channel: int) -> void:
	pass


## The handheld's sliding power switch, or null for a machine with a push button.
## The menu's Power row moves it rather than toggling behind its back, or the
## switch would stand at OFF on a running machine.
func power_slider() -> VRSlider:
	return _power_slider if is_instance_valid(_power_slider) else null


## Place the sockets built from av_port_channels, in that same order. Called once,
## with the ports already children of the system.
func configure_av_ports(_ports: Array) -> void:
	pass


## Adjust — or switch off — the printed legend round those sockets. Called once,
## straight after configure_av_ports, with the legend already laid out from the port
## positions; change any of its exports and call rebuild(). Default: leave it alone.
##
## Never called on a model wearing a detailed shell, which prints its own.
func configure_av_legend(_legend: AvLegend) -> void:
	pass


## Reposition the attach point for video-out channel `channel` (multi-output
## hardware). Channel 0 defaults to the classic single-port hook above; extra
## channels get a small sideways offset unless the model places them itself.
func configure_cable_attach_for(attach_point: Node3D, channel: int) -> void:
	configure_cable_attach(attach_point)
	# Channel 0 sits where the model put it; each further output steps 40 mm
	# along -X so a multi-output machine's leads do not share one exit.
	if channel != 0:
		attach_point.position += Vector3(-0.04 * channel, 0, 0)


## Point an attach point's cord-exit axis along `normal`, the outward normal of the
## face its port sits on, given in this model's own frame.
##
## VerletRope leaves a fixed anchor stiffly along that node's local -Z
## (VerletRope::PlugExitDir), so this is the whole of what decides which way a
## captive lead leaves the machine. Left at identity the cord runs out of the
## model's BACK whatever face the port ended up on — which on a handheld whose port
## moved to the side edge means the lead emerges from the flank and immediately
## doubles back along the body. It also aims PortVisual into the jack, the plug mesh
## being authored connector-on-+Z.
##
## The NES and the Atari 2600 wrote this out by hand — rotate -90 degrees about Y
## for a flank jack, identity for a rear panel — and this is the same rule for any
## face. Written through the GLOBAL transform because an attach point is a child of
## the SYSTEM, not of the model: the two frames coincide today, and a model that
## ever carries a transform of its own would silently aim every cord wrongly.
func aim_cable_exit(attach_point: Node3D, normal: Vector3) -> void:
	var n: Vector3 = (global_transform.basis.orthonormalized() * normal)
	if n.length_squared() < 0.0001:
		return
	n = n.normalized()
	# Any perpendicular will do for the roll — nothing about a cord cares which way
	# up its port is — but it must not lie along the normal itself.
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.99 else Vector3(0, 0, -1)
	var x := up.cross(n).normalized()
	attach_point.global_transform = Transform3D(
		Basis(x, (-n).cross(x), -n), attach_point.global_position)


## Offset from the video-out attach point where channel `channel`'s cable plug
## first stands, in the ATTACH POINT's own frame — so local -Z is the cord's exit
## axis (see aim_cable_exit) and the default simply trails the lead 100 mm straight
## out of the face its port is on. Local X runs along that face, which is what
## separates one channel's plug from the next.
##
## Read in the attach point's frame rather than in the world, so a machine standing
## at any angle — or simply picked up — lays its cord out of itself rather than
## toward world -Z.
func get_cable_spawn_offset(channel: int) -> Vector3:
	return Vector3(0.05 * channel, 0, -0.1)


## Adjust the root collision shape to fit this model. Custom non-handheld models
## whose geometry doesn't match the default console box (e.g. the tall Virtual
## Boy standing on its bipod) override this so the body rests on the ground
## instead of floating. Default: leave the scene's collision box unchanged.
## (Handhelds resize collision separately via configure_handheld_body.)
func configure_collision(_host: Node3D) -> void:
	pass


## How far past the slot mouth a slot-loaded disc rides, in metres, or 0 to take the
## cabinet's own default. Override on a machine whose case is too shallow for that
## default — a disc standing on edge in a 157 mm-deep Wii would otherwise finish 3 mm
## out through the back panel.
func slot_insert_depth() -> float:
	return 0.0


## Turn this shell's own disc mechanism with the platter, by `radians` about the
## spindle axis.
##
## RetroSystem already spins the DISC, and for a procedural bay that is the whole
## of it -- the box draws no mechanism, so there is nothing else to turn. A shell
## that models one is different: the PlayStation's clamp sits in the disc's
## centre hole and is visible THROUGH it, so a spinning platter around a fixed
## hub is a thing the player can see standing still.
##
## Handed an angle rather than a speed on purpose. The ramp lives in
## RetroSystem._update_disc_spin, which already knows about power, seating and
## spin-down, and a model second-guessing any of that would drift out of step
## with the disc it is supposed to be turning with.
func spin_disc_mechanism(_radians: float) -> void:
	pass


## Optional pivot node the seated disc should physically ride along with,
## instead of staying fixed to the console body (see MediaTray.disc_lid_pivot)
## — a flip-open tray assembly (the PSP's UMD door) where the disc's resting
## slot is part of the door itself, unlike a spindle console (PS1, GameCube...)
## where the disc rests on the BASE and only the lid mesh swings. Null
## (default): disc stays in its normal fixed seat.
func get_disc_lid_pivot() -> Node3D:
	return null


## Build this shell's disc mechanism on the host, and return it if it has one
## that moves. A bespoke shell brings its own geometry — its lid or shelf is part
## of the model — so the base builds nothing and answers null; the placeholder box
## draws one to match itself. `front` asks for a sliding shelf rather than a
## hinged lid, and `on_lid_swung` is told when a hand pushes a spring lid home.
func build_disc_bay(_host: Node3D, _slot: Node3D, _systemid: String, _front: bool,
		_on_lid_swung: Callable) -> ProceduralDiscBay:
	return null


## Draw the mouth a slot-loaded disc goes in through. Same split as
## build_disc_bay: a bespoke shell already has one.
## Put this machine's serial socket on it, if it has one.
##
## A hook rather than a fixed node on the cabinet because it is the SHELL that
## knows where the socket is: a model with a baked body has a moulded recess to
## sit it in, and the primitive box has only a back panel to lay it against. The
## cabinet cannot place something it cannot measure.
##
## Nothing here by default. A console with no serial port is the ordinary case,
## and a model that draws its own can override this without the cabinet caring.
func build_serial_port(_host: Node3D, _systemid: String) -> void:
	pass


## Whether this shell has an RJ45 socket of its own -- a slim PlayStation 2 has
## its network adapter built in, where a fat one takes a card -- and if so the
## link-bus port its core attaches it on (1 for a PS2); -1 for a console whose
## adapter is a card, or that has none. RetroSystem then builds the socket and
## the console counts as having its adapter in (ForcedCoreOptions.ethernet_adapter).
func builtin_ethernet_port() -> int:
	return -1


## Where a built-in RJ45 socket goes. A shell that draws one puts it there; this
## puts it at the end of the back panel, turned as the serial socket is so its +Z
## points out of the panel.
func place_builtin_ethernet_port(port: Node3D) -> void:
	port.position = Vector3(-0.075, 0.0, -0.126)
	port.rotation = Vector3(PI, 0.0, 0.0)


func build_disc_slit(_host: Node3D, _systemid: String) -> void:
	pass


## True when this model draws the machine's name itself, so the cabinet should not
## also lay its own nameplate on the front face.
##
## Separate from has_baked_shell(): a primitive can have every reason to print its
## own. The cabinet's plate is the SYSTEM name sized to 85% of the body width, which
## on a machine whose front reads "Wii" in a small grey mark puts "NINTENDO WII"
## across the whole foot of it.
func prints_own_name() -> bool:
	return false


## Group for a PRINTED LEGEND — the "POWER" / "3D" / "TOP" / "BOTTOM" text a
## device has silk-screened on its case, plus the system nameplate.
##
## A detailed shell already carries that printing in its own texture, so drawing
## ours over the top double-prints it; on the stand-ins, which have no texture at
## all, the legends are the only thing saying what a control does. Tag a label
## with this group and it appears on stand-ins only.
const PRINTED_LABEL_GROUP := "printed_label"


## Hide the printed legends on a detailed shell. No-op on a stand-in, which is
## the one place they earn their keep.
func hide_printed_labels() -> void:
	if not has_baked_shell():
		return
	for n in get_tree().get_nodes_in_group(PRINTED_LABEL_GROUP):
		if n is Node3D and is_ancestor_of(n):
			(n as Node3D).visible = false


## An editor-authored seat marker ("CartSeat" / "DiscSeat" / "UMDSeat"), whose
## global transform poses the seated media.
func _seat_marker(seat_name: String) -> Node3D:
	return find_child(seat_name, true, false) as Node3D


## Lookups that resolve against a DETAILED shell — socket markers, control meshes
## — have nothing to say on a plain model and must be skipped rather than left to
## come back null.
func _has_no_baked_shell() -> bool:
	return not has_baked_shell()


## Hide every editor-only seat preview box in the tree. There can be more than
## one — the device scene's and the stand-in's — and leaving either visible puts
## a translucent block through the shell at runtime.
func _hide_seat_previews() -> void:
	for n in find_children("SeatPreview", "Node3D", true, false):
		(n as Node3D).visible = false


## Reposition the cartridge snap zone to the model's physical slot location.
## Returns nothing: this hook only places the snap zone. The direction a
## cartridge travels into the slot is get_cartridge_insert_direction()'s.
func configure_cartridge_slot(_slot: Node3D) -> void:
	pass


## Reposition the console's SECOND native slot (the DS's Slot-2), when
## RetroSystem built one. Default: nothing, which is every console but the DS.
func configure_slot2(_slot: Node3D) -> void:
	pass


## Reposition the roof-top-centred ExpansionSocket RetroSystem just built (see
## _build_expansion_hardware) to wherever this model's real port actually is.
## Default: leave it where the generic placement put it -- correct for every
## shape that genuinely stacks an external box on top, which is everything
## that has shipped so far. The N64 is the first override, because its
## Expansion/Jumper Pak port is inside the body behind a cover, not on the roof.
func configure_expansion_socket(_socket: Node3D) -> void:
	pass


## Place a socket of a unit's own (ExpansionCatalog's row `socket`), which RetroSystem
## builds on the roof like the shared one. A model whose shell has the real opening
## puts it there (a Saturn's Video CD Card goes in behind its battery door); one
## that does not gets it here, through the middle of its back panel, with no plate.
## Left on the roof it was a connector drawn over the disc well of every console
## of a mod built before this hook, card or no card.
func configure_unit_socket(socket_id: String, socket: Node3D) -> void:
	var zone := socket as XRToolsSnapZone
	var host := socket.get_parent()
	if zone == null or host == null or not host.has_method("body_aabb"):
		return
	var box: AABB = host.call("body_aabb")
	if box.size.x <= 0.0:
		return
	var center := box.get_center()
	ExpansionPort.seat_through_back(zone,
		ExpansionCatalog.socket_size(str(host.get("systemid")), socket_id),
		Vector3(center.x, center.y, box.position.z))


## The slot this model's expansion-bay cover goes into, or null on a model with
## no such bay — which is every model but the N64, whose Jumper Pak sits under a
## lid that pulls off. RetroSystem asks so a save can record whether the lid is
## on the console or lying on a table, without persistence knowing the geometry.
func expansion_cover_slot() -> XRToolsSnapZone:
	return null


# ── the covers over a unit's own socket ───────────────────────────────────────

## unit socket id -> the slot its cover goes back into, and how big that cover is.
var _port_cover_slots: Dictionary = {}
var _port_cover_sizes: Dictionary = {}
## Covered openings shut from outside: the console is standing on the unit that
## fills one (RetroSystem.block_port_cover), so its cover cannot go back.
var _port_cover_blocked: Dictionary = {}


## Put a cover over one of the console's own unit sockets (ExpansionCatalog's
## row `socket`), for a shell whose real opening has one: the GameCube's Serial
## Port 1 under its cover, the fat PlayStation 2's EXPANSION BAY behind its own.
## Called from configure_unit_socket, once the socket is placed.
##
## `seat` is where the cover's middle goes, in this model's frame, its +Y out of
## the console; `size` is the cover's box (PortCover.size). The console seeds a
## cover into the slot on a fresh console (RetroSystem.seed_port_covers) and a
## save records whether it is on.
##
## The gate runs both ways. With the cover in, the socket is shut: a card held
## up to it does not go in, as it does not on the real console until the cover is
## off. With a card in, the slot is shut: the card is where the cover went.
func build_port_cover_slot(socket_id: String, socket: XRToolsSnapZone, seat: Transform3D,
		size: Vector3) -> XRToolsSnapZone:
	var zone := _port_cover_slots.get(socket_id) as XRToolsSnapZone
	if is_instance_valid(zone):
		return zone
	# Close, as the N64's lid slot is: a cover is pressed back into its own
	# opening, not lowered onto the console from across the table.
	zone = CoverSlots.make_zone(socket_id.to_pascal_case() + "CoverSlot",
		PortCover.group_for(socket_id), 0.06, self)
	zone.transform = seat
	_port_cover_slots[socket_id] = zone
	_port_cover_sizes[socket_id] = size
	_except_seated_cover(zone)
	# A null socket is an opening in the console's floor that a unit it stands
	# on fills (configure_cover_socket): there the unit asks the slot, and the
	# slot is shut by block_port_cover while the console stands on it.
	if socket == null:
		_gate_port_cover(socket_id, null)
		return zone
	var gate := _gate_port_cover.bind(socket_id, socket)
	zone.has_picked_up.connect(gate.unbind(1))
	zone.has_dropped.connect(gate)
	socket.has_picked_up.connect(gate.unbind(1))
	socket.has_dropped.connect(gate)
	gate.call()
	return zone


## A seated cover is frozen inside the console's own box, on the held layer the
## console collides with, and the slot moves it with the console every tick: it
## shoved the console it was in. A Super Famicom's EXT cover, 1 mm inside the
## floor, lifted the console 12 cm off a bare floor and tipped it back. So a
## cover and its console never touch while it is seated.
func _except_seated_cover(zone: XRToolsSnapZone) -> void:
	var seated: Array[PhysicsBody3D] = []
	zone.has_picked_up.connect(func(what: Node3D) -> void:
		var host := get_parent() as PhysicsBody3D
		var cover := what as PhysicsBody3D
		if host != null and cover != null:
			host.add_collision_exception_with(cover)
			seated.append(cover))
	zone.has_dropped.connect(func() -> void:
		var host := get_parent() as PhysicsBody3D
		for cover in seated:
			if host != null and is_instance_valid(cover):
				host.remove_collision_exception_with(cover)
		seated.clear())


## Cover one of the openings in the console's floor that a unit it stands on
## plugs into (ExpansionCatalog's row `cover_socket`: the N64's EXT under the
## 64DD, a Super NES's EXT under the Satellaview). A model whose shell has that
## cover calls build_port_cover_slot(socket_id, null, seat, size) here; the
## default has none, and the console stands on the unit as it always did.
func configure_cover_socket(_socket_id: String) -> void:
	pass


## Shut or open a floor opening's cover slot from outside: shut while the console
## stands on the unit that fills the opening.
func block_port_cover(socket_id: String, blocked: bool) -> void:
	_port_cover_blocked[socket_id] = blocked
	_gate_port_cover(socket_id, null)


## The slot a unit socket's cover goes into, or null for a socket with no cover
## -- every socket on a model that never called build_port_cover_slot.
func port_cover_slot(socket_id: String) -> XRToolsSnapZone:
	var zone := _port_cover_slots.get(socket_id) as XRToolsSnapZone
	return zone if is_instance_valid(zone) else null


## The sockets that have a cover slot, in the order they were built.
func port_cover_sockets() -> Array[String]:
	var out: Array[String] = []
	for socket_id: String in _port_cover_slots:
		if port_cover_slot(socket_id) != null:
			out.append(socket_id)
	return out


## How big the cover over `socket_id` is (PortCover.size), or ZERO for none.
func port_cover_size(socket_id: String) -> Vector3:
	return _port_cover_sizes.get(socket_id, Vector3.ZERO)


func _gate_port_cover(socket_id: String, socket: XRToolsSnapZone) -> void:
	var zone := port_cover_slot(socket_id)
	if zone == null:
		return
	if socket == null:
		zone.enabled = not bool(_port_cover_blocked.get(socket_id, false))
		return
	if not is_instance_valid(socket):
		return
	socket.enabled = not zone.has_snapped_object()
	zone.enabled = not socket.has_snapped_object()


## The world-space direction a cartridge travels when being inserted.
## Returned as a unit vector; the animation moves FROM final_pos - dir*depth TO final_pos.
func get_cartridge_insert_direction() -> Vector3:
	return Vector3.UP


## Play the reset animation (e.g. depress the reset button, reboot LED flash).
## Called by RetroSystem.reset() independently of the power on/off hooks.
func play_reset() -> void:
	pass


## Animate a cartridge ejecting from its slot before it is dropped.
## NOTE: by the time has_dropped fires the cartridge is already released, so
## this is reserved for future use (e.g. intercepting the drop earlier).
func play_cartridge_eject(_cartridge: Node3D, _slot: Node3D) -> void:
	pass


# ── Power LED ─────────────────────────────────────────────────────────────────
#
# A lit lens plus a companion OmniLight3D, shared by the shells detailed enough
# to have a real one. The NES and the PlayStation had a line-for-line copy each,
# differing only in the emission colour and how hard the lens is driven.
#
# The light is a separate node rather than emission alone because an emissive
# surface lights nothing around it: without the omni the lens glows and the
# plastic beside it stays dark.

## Shared by every shell with a lit lens. DECAY and RANGE are the falloff of a
## few-millimetre source, and STANDOFF is how far in front of the lens the omni
## sits. LED_ENERGY and the colour are NOT here: each console's lens is a
## different brightness and hue, measured per shell.
const LED_DECAY := 2.0
const LED_RANGE := 0.45
const LED_STANDOFF := 0.006


## Whether a lamp may hang a real light off its lens. Forward+ only.
##
## This light is a deliberately extreme thing: an energy of ~1e-5 sitting 3 to 6
## mm off the surface, whose brightness comes out of the inverse square at that
## range (peak * STANDOFF^2). Forward+ renders it as intended. The MOBILE backend
## — Android, so the Quest — does not, and not subtly: at the shipped values with
## specular 0 it paints everything the light reaches BLACK (the DualShock's lamp
## became a black bar, the PlayStation's green lens grew a dark core); nudging
## specular off zero clears the black but leaves a flat coloured disc that reads
## as a sticker rather than a light; and steepening the falloff detonates
## completely, the whole pad black with saturated patches. Three regimes, three
## different wrong answers, so this is not a value that wants tuning.
##
## The lens's own emissive material is untouched by any of it and renders
## identically on both backends. Mobile therefore keeps the glowing lens and
## gives up the wash it throws on the shell around it — which is exactly what
## these shells looked like before the lamps were added, and is a great deal
## better than a black hole where the lamp should be.
static func lamp_glow_supported() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

var _power_light_mesh: MeshInstance3D = null
var _power_light_mats: Array[StandardMaterial3D] = []
var _power_light_glow: OmniLight3D = null
var _power_light_energy := 1.0


## Make the lens emissive and hang a glow in front of it. Call once, after
## _power_light_mesh is resolved; set_power_light drives it afterwards.
##
## `emission` is the colour the lens itself radiates and `glow` what the omni
## casts — related but not equal, since the lens reads brighter than the light it
## throws. `lit_energy` is how hard the lens is driven when on: the NES's red
## takes 3.0 where the PlayStation's green takes 1.0 for the same apparent
## brightness, which is a luminance difference and not a tuning accident.
func prep_power_light(emission: Color, glow: Color, glow_energy: float,
		lit_energy: float) -> void:
	if _power_light_mesh == null:
		return
	_power_light_energy = lit_energy
	_power_light_mats.clear()
	for s in range(_power_light_mesh.mesh.get_surface_count()):
		var src := _power_light_mesh.get_active_material(s) as BaseMaterial3D
		var m := StandardMaterial3D.new()
		if src != null:
			m.albedo_color = src.albedo_color
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 0.0
		_power_light_mesh.set_surface_override_material(s, m)
		_power_light_mats.append(m)
	_build_power_glow(glow, glow_energy)


func _build_power_glow(glow: Color, glow_energy: float) -> void:
	if _power_light_glow != null or _power_light_mesh == null:
		return
	if not lamp_glow_supported():
		return
	_power_light_glow = OmniLight3D.new()
	_power_light_glow.name = "PowerLightGlow"
	_power_light_glow.add_to_group("no_shadow")
	_power_light_glow.light_color = glow
	_power_light_glow.light_energy = glow_energy
	_power_light_glow.omni_range = LED_RANGE
	_power_light_glow.omni_attenuation = LED_DECAY
	# A point source millimetres from glossy ABS throws a specular highlight the
	# real lens cannot. Its reflection comes from the emissive mesh instead.
	_power_light_glow.light_specular = 0.0
	_power_light_glow.shadow_enabled = false
	_power_light_glow.distance_fade_enabled = true
	_power_light_glow.distance_fade_begin = 3.0
	_power_light_glow.distance_fade_length = 1.5
	_power_light_glow.visible = false
	add_child(_power_light_glow)
	# Measured off the lens rather than quoted from the asset: _ready recentres
	# the shell on its own footprint, so the GLB's coordinates are not this
	# node's.
	var to_model := global_transform.affine_inverse() * _power_light_mesh.global_transform
	var lens: Vector3 = to_model * _power_light_mesh.get_aabb().get_center()
	_power_light_glow.position = lens + Vector3(0.0, 0.0, LED_STANDOFF)


func set_power_light(on: bool) -> void:
	for m in _power_light_mats:
		m.emission_energy_multiplier = _power_light_energy if on else 0.0
	if _power_light_glow != null:
		# Hidden rather than dimmed to zero: an energy-0 light is still a light
		# the renderer culls and binds per object.
		_power_light_glow.visible = on
