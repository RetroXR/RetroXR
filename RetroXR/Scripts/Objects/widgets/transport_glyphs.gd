## TransportGlyphs — the transport symbols the TV remote prints, shared with the
## front panels of the decks it drives.
##
## One table for both, so a deck's PLAY key and the remote's PLAY key cannot drift
## into two different symbols. The codepoints are Font Awesome / Material Design
## in the Symbols Nerd Font, which has to be chained onto the label's own font or
## every one of them renders as tofu.
class_name TransportGlyphs

const FONT_PATH := "res://fonts/SymbolsNerdFont-Regular.ttf"

const CODES := {
	"play": 0xF04B, "pause": 0xF04C, "stop": 0xF04D,
	"ff": 0xF04E, "rew": 0xF04A, "next": 0xF051, "prev": 0xF048,
	"vol_up": 0xF028, "vol_down": 0xF027, "power": 0xF011, "menu": 0xF0C9,
	"up": 0xF077, "down": 0xF078, "left": 0xF053, "right": 0xF054,
	"ok": 0xF192, "mute": 0xEEE8, "eject": 0xF052,
	"audio": 0xF1AB, "subtitle": 0xF0A16,
	# The TV's own switches.
	"source": 0xF090,     # fa-sign_in       — which input the set is showing
	# Channel up/down are deliberately NOT the "up"/"down" keys above: those are
	# fa-chevron, the DVD's menu D-pad, and one arrow shared between "move the
	# cursor" and "next channel" reads as one control. Codicon solid arrows are a
	# different family, so the two separate at a glance.
	"ch_up": 0xEAA1,      # cod-arrow_up
	"ch_down": 0xEA9A,    # cod-arrow_down
	"crt": 0xF26C,        # fa-tv            — the picture filter
	# Picture shape. Two glyphs, not one key with a label: the handset shows the
	# shape the set is IN, so the key reads as a state like the audio and 3D keys
	# beside it rather than as a word.
	#
	# Codepoints verified against the shipped font's cmap, not guessed — the first
	# pair here rendered a clapperboard and a multiplication sign, because in this
	# build F0381/F0382 are md-movie and md-multiplication.
	"aspect_4_3": 0xF01A2,    # md-crop_square    — the tube's own shape
	"aspect_16_9": 0xF01A0,   # md-crop_landscape — letterboxed wide
	"stereo": 0xF07FD,    # md-video_3d      — both eyes
	"eye": 0xF1A1C,       # md-eye-outline   — one eye, biased to its own side
	"audio_stereo": 0xF0D38,  # md-speaker-multiple — both channels
	"audio_mono": 0xF04C3,    # md-speaker          — one channel, biased likewise
	"audio_out": 0xF1120,     # md-volume_source    — where the set sends its sound
	# The PC tower's back panel names its sockets with these rather than with words.
	# "speakers" is the same codepoint as audio_stereo and kept separate anyway: one
	# is a deck saying which channels it carries, the other is a socket saying what
	# plugs into it, and they have no reason to move together.
	"mouse": 0xEFBA,
	"keyboard": 0xF030C,
	# The same codepoint the Scroll Lock capture icon uses on a held pad, kept
	# here so the receiver dongle and that icon cannot drift into two symbols.
	"gamepad": 0xEC17,
	"sticker": 0xF136B,   # md-sticker — a poster is about to stick here
	# Prefixed to a device glyph to say "the wireless one" — a receiver's whole
	# reason for existing is that the real device is paired rather than cabled.
	"bluetooth": 0xF294,
	"vga": 0xF0379,
	"speakers": 0xF0D38,
}

## How far a side-biased glyph leans off centre, in the button's local X. The cap
## is 25 mm and a TV_SIZE glyph is most of that, so this is a lean rather than a
## move: enough to read as "this side", not enough to hang off the edge.
const SIDE_SHIFT := 0.005

## A glyph carries a whole word's meaning in one character, so it is set larger
## than the word it replaces (the decks printed PLAY at 10, the TV CRT at 16).
const DECK_SIZE := 20
const TV_SIZE := 24

## Built once. A FontVariation is immutable in use here and every label wants the
## same one.
static var _font: Font = null


## The glyph for a key, or "?" for one that isn't in the table — visible in the
## world rather than silently blank.
static func glyph(key: String) -> String:
	return String.chr(int(CODES.get(key, 0x3F)))


## The project default as the base, so a label that still carries words renders
## them, with the symbol font behind it for the icon codepoints.
static func font() -> Font:
	if _font == null:
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		var symbols: Font = load(FONT_PATH)
		if symbols != null:
			fv.fallbacks = [symbols]
		_font = fv
	return _font


## Print a glyph on each named button's ButtonLabel. `map` is button node name ->
## glyph key. A button the scene doesn't have is skipped, so one table can cover a
## family of decks that share most of a transport.
##
## `font_size` is passed rather than kept: a glyph carries a whole word's meaning
## in one character and wants to be bigger than the word was.
static func label_buttons(host: Node, map: Dictionary, font_size: int) -> void:
	for btn_name: String in map:
		set_glyph(host, btn_name, str(map[btn_name]), font_size)


## One button's glyph, optionally leaning to one side of the cap: `side` is -1
## for left, +1 for right, 0 centred. A tri-state switch reads its own state that
## way — which channel or which eye it is on — without a second symbol.
##
## The label's authored X is remembered on first use, so re-printing a leaning
## glyph on every toggle cannot walk the label off the cap.
static func set_glyph(host: Node, btn_name: String, key: String, font_size: int,
					  side: float = 0.0) -> void:
	var lbl := host.get_node_or_null("%s/ButtonLabel" % btn_name) as Label3D
	if lbl == null:
		return
	if not lbl.has_meta("glyph_home_x"):
		lbl.set_meta("glyph_home_x", lbl.position.x)
	lbl.font = font()
	lbl.font_size = font_size
	lbl.text = glyph(key)
	lbl.position.x = float(lbl.get_meta("glyph_home_x")) + side * SIDE_SHIFT
