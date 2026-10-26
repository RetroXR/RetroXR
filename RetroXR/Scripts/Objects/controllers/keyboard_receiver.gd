## KeyboardReceiver — the real keyboard, forwarded to the port it is plugged into.
##
## The virtual RetroKeyboard has to be HELD and Scroll-Lock captured before your
## typing reaches a core, which costs you a hand and a mode. This is the same
## thing as an object: seat it in a computer's port and type.
##
## ── Why there is no capture here ─────────────────────────────────────────────
## ScrollLockCapture makes the held board's hijacking of the keyboard opt-in,
## because holding a board is an ambiguous thing to be doing — you might merely be
## carrying it. Plugging a receiver in is not ambiguous. Seated is live, and the
## dongle is a visible object with a green light on it, which is easier to find
## again than a mode you toggled with a key.
##
## ── Which keyboard, and which of several receivers ───────────────────────────
## There is one keyboard, so there is nothing to select — unlike a gamepad, which
## names its device. Several RetroKeyboards can exist at once and the GRIP decides
## which of them your typing drives; a receiver is never held, so instead each one
## forwards to its own port and two seated receivers both receive. A fan-out, not
## an ambiguity: you cannot type at two machines at once, and seating two is how
## you asked for both.
##
## VR only — see the spawn menu. On desktop the real keyboard IS the player: WASD
## walks, and a dongle silently taking it would fight the controls you are
## standing on. Desktop keeps the held board and its capture, untouched.
class_name KeyboardReceiver
extends InputReceiver

const RETRO_DEVICE_KEYBOARD := 3

## Keys currently down THROUGH THIS RECEIVER, so unplugging can release them.
## A core that never sees the key-up spends the rest of the session believing
## the key is held.
var _down: Dictionary = {}


func _ready() -> void:
	device_type = RETRO_DEVICE_KEYBOARD
	super._ready()


## The PS/2 plug the held RetroKeyboard wears, named from that class so the two cannot
## drift apart. The same connector whatever the machine: a keyboard is a
## keyboard, and only a pad takes the console's own moulding.
func connector_for(_sysid: String) -> String:
	return RetroKeyboard.PLUG_MESH


func receiver_glyph() -> String:
	# Bluetooth first: this box is for the paired keyboard, not a cabled one.
	return TransportGlyphs.glyph("bluetooth") + " " + TransportGlyphs.glyph("keyboard")


## Nothing printed: the Bluetooth mark and the device symbol say it.
func case_text() -> String:
	return ""


func receiver_label() -> String:
	return "KEYBOARD"


## Lit whenever it is seated: there is one keyboard and it is always attached, so
## unlike a pad this can never be plugged in and bound to nothing.
func is_bound() -> bool:
	return true


func on_going_idle() -> void:
	_release_all()


func _exit_tree() -> void:
	super._exit_tree()
	_release_all()


# ── Input ─────────────────────────────────────────────────────────────────────

## Typing into a menu field is not typing at the game. TypingGuard sets the
## suspension globally the moment a LineEdit takes focus — "the keyboard is one
## device, so if it is composing text it is not driving any held device" — and a
## receiver is no different for being unheld.
##
## Deliberately does NOT mark the event handled. The held RetroKeyboard does,
## to stop keys it has captured from also moving the player — but consuming here
## would mean the FIRST receiver to see a keystroke swallowed it, and the second
## machine got nothing. Two seated receivers are a fan-out, so every one of them
## has to see the same event. Safe because these are VR-only, where locomotion is
## the stick and no key moves the player.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.is_echo() or not is_live():
		return
	if ScrollLockCapture.is_suspended():
		return
	_send_key(key, key.is_pressed())


## One real-keyboard transition. Takes the whole event: GodotKeyToRetroKey reads
## its `location` to tell left and right Shift/Ctrl/Alt/Super apart, which a bare
## keycode cannot. Returns true when consumed.
func _send_key(event: InputEventKey, pressed: bool) -> bool:
	var lib: Libretro = _connected_system.get_libretro_node()
	if lib == null:
		return false
	var keycode: int = lib.GodotKeyToRetroKey(event)
	if keycode == 0:
		return false
	if pressed:
		_down[keycode] = true
	else:
		_down.erase(keycode)
	var character := int(event.unicode)
	if character == 0 and keycode >= 32 and keycode <= 126:
		character = keycode
	# Netplay: key events ride the deterministic frame schedule.
	if NetworkManager.netplay_queue_key(_connected_system, keycode, pressed, character):
		return true
	# Port 0, as every keyboard in this project reports — a keyboard claims no
	# port of its own on a computer system (RetroSystem._claims_port_device).
	lib.SetKeyState(0, keycode, pressed, character)
	return true


## Let go of everything still held. Unplugging mid-keystroke otherwise leaves the
## core holding it down forever.
func _release_all() -> void:
	if not is_instance_valid(_connected_system):
		_down.clear()
		return
	var lib: Libretro = _connected_system.get_libretro_node()
	if lib != null:
		for keycode: int in _down:
			lib.SetKeyState(0, keycode, false, 0)
	_down.clear()
