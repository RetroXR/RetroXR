## Sjis — Shift-JIS save titles, decoded for a label.
##
## Both Sony consoles (and the Dreamcast) write a save's title in Shift-JIS and
## almost always in the FULL-WIDTH forms, so reading the bytes as ASCII yields
## mojibake. Full-width letters, digits and the common punctuation come back as
## plain ASCII, which is what a Western title wants ("ＦＩＮＡＬ" reads "FINAL").
## Everything else -- kana, kanji, Japanese brackets and symbols -- is looked up
## in SjisTable (code page 932, generated) and kept as itself. Until 2026-11-05
## that half was dropped, so a Japanese title listed as whatever ASCII it held:
## Dokodemo Crash-kun as "3", Ikaruga as "()".
##
## Lifted out of PS1Card when the PlayStation 2's icon.sys needed the same
## decode. PS1Card forwards to it, so the two cannot drift.
class_name Sjis


const PUNCT := {
	0x8140: " ", 0x8141: ",", 0x8142: ".", 0x8143: ",", 0x8144: ".",
	0x8146: ":", 0x8147: ";", 0x8148: "?", 0x8149: "!", 0x814F: "^",
	0x8151: "_", 0x815B: "-", 0x815C: "-", 0x815D: "-", 0x815E: "/",
	0x815F: "\\", 0x8160: "~", 0x8162: "|", 0x8165: "'", 0x8166: "'",
	0x8167: "\"", 0x8168: "\"", 0x8169: "(", 0x816A: ")", 0x816D: "[",
	0x816E: "]", 0x816F: "{", 0x8170: "}", 0x817B: "+", 0x817C: "-",
	0x8181: "=", 0x8183: "<", 0x8184: ">", 0x8190: "$", 0x8193: "%",
	0x8194: "#", 0x8195: "&", 0x8196: "*", 0x8197: "@",
}

const _NOT_A_CHAR := 0xFFFD

## SjisTable.ROWS with its line breaks taken out, built on first use.
static var _flat := ""
static var _table_broken := false


## A title as text: ASCII where the console wrote it in full-width, Japanese as
## Japanese. Stops at the first NUL, drops bytes that are no character.
static func to_text(raw: PackedByteArray) -> String:
	var s := ""
	var i := 0
	while i < raw.size():
		var b := raw[i]
		if b == 0:
			break
		# Some games just write plain ASCII.
		if b < 0x80:
			s += char(b)
			i += 1
			continue
		# Half-width katakana are ONE byte.
		if b >= 0xA1 and b <= 0xDF:
			s += char(0xFF61 + (b - 0xA1))
			i += 1
			continue
		# Not a lead byte (0x80, 0xA0, 0xFD-0xFF): skip it alone, so the byte after
		# it is still read as the start of a character.
		if not _is_lead(b):
			i += 1
			continue
		if i + 1 >= raw.size():
			break
		var trail := raw[i + 1]
		var w := (b << 8) | trail
		i += 2
		if w >= 0x824F and w <= 0x8258:
			s += char(0x30 + (w - 0x824F))        # full-width 0-9
		elif w >= 0x8260 and w <= 0x8279:
			s += char(0x41 + (w - 0x8260))        # full-width A-Z
		elif w >= 0x8281 and w <= 0x829A:
			s += char(0x61 + (w - 0x8281))        # full-width a-z
		elif PUNCT.has(w):
			s += str(PUNCT[w])
		else:
			var c := _wide(b, trail)
			if c != 0:
				s += char(c)
	# The ideographic space is a title's usual padding, and strip_edges() keeps it.
	return s.strip_edges().lstrip("　").rstrip("　").strip_edges()


## True when `s` holds something to read -- a letter, a digit, kana or kanji --
## rather than only brackets, symbols and spaces ("()" alone is no title).
static func has_words(s: String) -> bool:
	for i in range(s.length()):
		var c := s.unicode_at(i)
		if (c >= 0x30 and c <= 0x39) or (c >= 0x41 and c <= 0x5A) or (c >= 0x61 and c <= 0x7A):
			return true
		if c >= 0x0391 and c <= 0x04FF:            # Greek and Cyrillic, both in JIS X 0208
			return true
		if c >= 0x3041 and c <= 0x30FF and c != 0x30FB:   # kana, not the middle dot
			return true
		if c >= 0x4E00 and c <= 0x9FFF:            # kanji
			return true
		if c >= 0xFF66 and c <= 0xFF9F:            # half-width katakana
			return true
	return false


static func _is_lead(b: int) -> bool:
	return (b >= 0x81 and b <= 0x9F) or (b >= 0xE0 and b <= 0xFC)


## The code point for a lead and trail byte, or 0 for none.
static func _wide(lead: int, trail: int) -> int:
	if trail < SjisTable.TRAIL_FIRST or trail >= SjisTable.TRAIL_FIRST + SjisTable.TRAIL_COUNT:
		return 0
	if _flat.is_empty():
		if _table_broken:
			return 0
		_flat = SjisTable.ROWS.replace("\r", "").replace("\n", "")
		if _flat.length() != SjisTable.ROW_COUNT * SjisTable.TRAIL_COUNT:
			push_error("[Sjis] SjisTable holds %d characters, not %d: kana and kanji will be dropped (re-run Tools/gen_sjis_table.py)"
				% [_flat.length(), SjisTable.ROW_COUNT * SjisTable.TRAIL_COUNT])
			_flat = ""
			_table_broken = true
			return 0
	var row := lead - 0x81 if lead <= 0x9F else 31 + lead - 0xE0
	var c := _flat.unicode_at(row * SjisTable.TRAIL_COUNT + trail - SjisTable.TRAIL_FIRST)
	return 0 if c == _NOT_A_CHAR else c
