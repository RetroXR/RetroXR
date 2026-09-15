## SearchFold — the form a search compares text in: lowercase, accents removed.
##
## Fold both the query and the text, so "pokemon" finds "Pokémon" and "pokémon"
## finds "Pokemon". Decomposed text (a letter followed by a combining mark) folds
## the same as precomposed. Scripts without a Latin base letter pass through.
class_name SearchFold
extends RefCounted

const _LETTERS := {
	"a": "àáâãäåāăą",
	"ae": "æ",
	"c": "çćĉċč",
	"d": "ðďđ",
	"e": "èéêëēĕėęě",
	"g": "ĝğġģ",
	"h": "ĥħ",
	"i": "ìíîïĩīĭįı",
	"ij": "ĳ",
	"j": "ĵ",
	"k": "ķ",
	"l": "ĺļľŀł",
	"n": "ñńņň",
	"o": "òóôõöøōŏő",
	"oe": "œ",
	"r": "ŕŗř",
	"s": "śŝşš",
	"ss": "ß",
	"t": "ţťŧ",
	"th": "þ",
	"u": "ùúûüũūŭůűų",
	"w": "ŵ",
	"y": "ýÿŷ",
	"z": "źżž",
}

const _COMBINING_FIRST := 0x0300
const _COMBINING_LAST := 0x036F

static var _base_of: Dictionary = _invert(_LETTERS)
static var _non_ascii: RegEx = RegEx.create_from_string("[^\\x00-\\x7f]+")


static func fold(text: String) -> String:
	var lower := text.to_lower()
	var runs := _non_ascii.search_all(lower)
	if runs.is_empty():
		return lower
	var parts := PackedStringArray()
	var at := 0
	for run: RegExMatch in runs:
		parts.append(lower.substr(at, run.get_start() - at))
		for c: String in run.get_string():
			var code := c.unicode_at(0)
			if code >= _COMBINING_FIRST and code <= _COMBINING_LAST:
				continue
			parts.append(_base_of.get(c, c))
		at = run.get_end()
	parts.append(lower.substr(at))
	return "".join(parts)


static func _invert(letters: Dictionary) -> Dictionary:
	var out := {}
	for base: String in letters:
		for c: String in letters[base]:
			out[c] = base
	return out
