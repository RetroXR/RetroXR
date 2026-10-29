## RetroSystemModelGameBoy — original DMG Game Boy (portrait, 160×144 LCD).
## The stand-in shell lives in game_boy_primitive.tscn.
class_name RetroSystemModelGameBoy
extends RetroSystemModelHandheld

## Classic DMG dot-matrix green LCD filter, applied to the built-in screen.
const LCD_SHADER := preload("res://Shaders/gameboy_lcd.gdshader")
## The same look lit by the room — the DMG's reflective panel had no light.
const LCD_LIT_SHADER := preload("res://Shaders/gameboy_lcd_lit.gdshader")


func _init() -> void:
	# Game Boy uses the base default cartridge size (57 × 65 × 8 mm).
	_lcd_shader = LCD_SHADER
	_lcd_shader_lit = LCD_LIT_SHADER
	_reflective_lcd = true




## Align the cart with the shell's own slot marker ACROSS the body — the base
## centres it on the body's mid-plane, but the DMG's connector sits ~1 cm below
## that, so on a 3 cm-thick shell the card sat visibly off the real slot.
##
## Only x/y come from the marker; the depth is set so the cart's outer end lands
## FLUSH with the top of the shell, like real hardware — a Game Boy cartridge
## drops fully into the back recess rather than standing proud. (Seating the
## contacts on the marker instead left 30 mm of a 65 mm cart hanging out, and
## the base's _cart_protrude() convention still left ~18 mm.) The marker's basis
## already encodes the right pose — length running out of the top mouth, label
## facing the console's back.
## Falls back to the base placement when the detailed GLB is absent.
func configure_cartridge_slot(slot: Node3D) -> void:
	super(slot)
	# On the stand-in, super()'s CartSeat is the last word — socket_media marks
	# the DETAILED shell's connector.
	if _has_no_baked_shell():
		return
	var sock := find_child("socket_media", true, false) as Node3D
	if sock == null:
		return
	var b: Basis = (global_transform.basis.inverse() * sock.global_transform.basis).orthonormalized()
	var p: Vector3 = to_local(sock.global_position)
	var seat_z := -body_size.z * 0.5 + cart_size.y * 0.5
	slot.transform = Transform3D(b, Vector3(p.x, p.y, seat_z))


## Hand the power switch the shell's own cap ("Pulsante_Accensione", the tab on
## the top edge) instead of leaving it driving a hidden placeholder KnobMesh.
##
## Direction and throw are authored on the slider in game_boy.tscn: the DMG
## moulds "OFF ◄ ► ON" into the top edge and ships the cap parked at the -X end
## of its slot, which is OFF — so ON is +X. The slot is ~10 mm long against a
## 4 mm cap, hence the 6 mm throw.
func _on_shell_ready() -> void:
	if _power_switch == null or _glb == null:
		return
	var cap := _glb.find_child("Pulsante_Accensione", true, false) as MeshInstance3D
	if cap != null:
		_power_switch.set_knob_mesh(cap)


## PHONES, on the bottom edge just left of centre: 4.7 mm of a 90 mm body on the
## DMG-01 (RetroXR-models nintendo/gb/console, its HeadphonePort).
func headphone_jack() -> Dictionary:
	return edge_jack(-0.052)
