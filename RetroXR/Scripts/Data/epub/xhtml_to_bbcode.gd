extends RefCounted
## Converts one EPUB chapter's XHTML body into the BBCode subset src/ui/reader.tscn's
## RichTextLabel renders (PM decision 5, docs/MEDIA_SYSTEM_DESIGN.md section 8/M5 package
## F). Pure - no file/network access, no Godot node, safe to unit-test directly.
##
## Deliberately NOT built on XMLParser: real-world EPUB XHTML frequently carries entities
## (`&nbsp;` chief among them) that are only legal under an XHTML DTD a strict XML parser
## won't fetch, and one malformed/unclosed tag anywhere in a chapter would otherwise blank
## the whole page. A small hand-rolled tag/text tokenizer degrades gracefully instead:
## unknown or slightly-off markup just falls through as stripped tags around kept text.
##
## Handling summary:
##   h1-h6      -> [font_size=N]...[/font_size], one blank line after
##   p, br      -> paragraph breaks / line breaks
##   b, strong  -> [b]...[/b]        i, em -> [i]...[/i]        u -> [u]...[/u]
##   blockquote -> [indent]...[/indent]
##   ul, li     -> "• " bullets, nested lists indented one level further
##   ol, li     -> "N. " numbered bullets, nested lists indented one level further
##   img        -> stripped, replaced with a "[image omitted]" placeholder line
##   a          -> tag stripped, link text kept
##   head/script/style/title -> element and its whole text content dropped
##   anything else -> tag stripped, inner text kept
## Entities: &amp; &lt; &gt; &quot; &#39; &nbsp; (named and numeric decimal/hex) decoded.
## Runs of whitespace collapse to a single space; the tag/text tokenizer, not layout, owns
## line breaks, so authors' source indentation never leaks into the rendered page.

const HEADING_SIZES := {
	"h1": 28, "h2": 24, "h3": 21, "h4": 19, "h5": 17, "h6": 16,
}

## Elements whose entire content (tags and text alike) is dropped.
const SKIP_CONTENT_TAGS := ["head", "script", "style", "title"]

## Elements with no meaningful content of their own - stripped without a placeholder.
const TRANSPARENT_TAGS := [
	"a", "span", "div", "html", "body", "header", "footer", "section", "article",
	"nav", "figure", "figcaption", "small", "sup", "sub", "abbr", "cite", "code",
	"pre", "hr", "table", "thead", "tbody", "tr", "td", "th",
]

const TAG_RE := "<(/?)\\s*([a-zA-Z][a-zA-Z0-9]*)([^>]*?)(/?)\\s*>"
const NUMERIC_ENTITY_RE := "&#(x[0-9a-fA-F]+|[0-9]+);"
const WHITESPACE_RE := "[ \\t\\r\\n]+"
## XML prolog, DOCTYPE and comments: not tags (TAG_RE needs a letter first), so without
## this they would leak into the text as "<?xml version=..." on a book's first page.
const PROLOG_RE := "<\\?[\\s\\S]*?\\?>|<!DOCTYPE[^>]*>|<!--[\\s\\S]*?-->"

static var _tag_regex: RegEx = null
static var _numeric_entity_regex: RegEx = null
static var _whitespace_regex: RegEx = null
static var _prolog_regex: RegEx = null


static func _ensure_regexes() -> void:
	if _tag_regex != null:
		return
	_tag_regex = RegEx.new()
	_tag_regex.compile(TAG_RE)
	_numeric_entity_regex = RegEx.new()
	_numeric_entity_regex.compile(NUMERIC_ENTITY_RE)
	_whitespace_regex = RegEx.new()
	_whitespace_regex.compile(WHITESPACE_RE)
	_prolog_regex = RegEx.new()
	_prolog_regex.compile(PROLOG_RE)


## Converts one XHTML document/fragment's markup into BBCode text.
static func convert(raw_xhtml: String) -> String:
	_ensure_regexes()
	var xhtml: String = _prolog_regex.sub(raw_xhtml, "", true)

	var out := ""
	var pos := 0
	var length := xhtml.length()

	var list_stack: Array = []      # each entry: {"type": "ul"/"ol", "count": int}
	var skip_depth := 0             # >0 while inside a SKIP_CONTENT_TAGS element

	while pos < length:
		var m: RegExMatch = _tag_regex.search(xhtml, pos)
		if m == null:
			out += _emit_text(xhtml.substr(pos), skip_depth)
			break

		if m.get_start() > pos:
			out += _emit_text(xhtml.substr(pos, m.get_start() - pos), skip_depth)

		var closing: bool = m.get_string(1) == "/"
		var tag: String = m.get_string(2).to_lower()
		var self_closing: bool = m.get_string(4) == "/"
		pos = m.get_end()

		if skip_depth > 0:
			if tag in SKIP_CONTENT_TAGS:
				if closing:
					skip_depth -= 1
				elif not self_closing:
					skip_depth += 1
			continue

		if tag in SKIP_CONTENT_TAGS:
			if not closing and not self_closing:
				skip_depth += 1
			continue

		if HEADING_SIZES.has(tag):
			if closing:
				out += "[/font_size]\n\n"
			else:
				out += "[font_size=%d]" % HEADING_SIZES[tag]
				if self_closing:
					out += "[/font_size]\n\n"
			continue

		match tag:
			"p":
				if closing or self_closing:
					out += "\n\n"
			"br":
				out += "\n"
			"b", "strong":
				out += "[/b]" if closing else "[b]"
			"i", "em":
				out += "[/i]" if closing else "[i]"
			"u":
				out += "[/u]" if closing else "[u]"
			"blockquote":
				if closing:
					out += "[/indent]\n\n"
				else:
					out += "[indent]"
			"ul", "ol":
				if closing:
					if not list_stack.is_empty():
						list_stack.pop_back()
					out += "\n"
				else:
					if not list_stack.is_empty():
						out += "\n"
					list_stack.append({"type": tag, "count": 0})
					if self_closing:
						list_stack.pop_back()
			"li":
				if not closing:
					out += _list_bullet(list_stack)
					if self_closing:
						out += "\n"
				else:
					out += "\n"
			"img":
				if not closing:
					out += "[image omitted]\n"
			_:
				pass  # unknown/transparent tags (including TRANSPARENT_TAGS) are stripped

	return _finalize(out)


## One list-item bullet ("• " or "N. "), indented by nesting depth, and bumps the
## innermost list's counter when it is an ordered list.
static func _list_bullet(list_stack: Array) -> String:
	if list_stack.is_empty():
		return "• "
	var depth: int = list_stack.size() - 1
	var indent: String = "    ".repeat(depth)
	var top: Dictionary = list_stack[list_stack.size() - 1]
	if top["type"] == "ol":
		top["count"] += 1
		return "%s%d. " % [indent, int(top["count"])]
	return "%s• " % indent


## Decodes entities and collapses whitespace in one text run; "" while inside a
## SKIP_CONTENT_TAGS element (its text never reaches the output). A text run that is
## pure whitespace AND spans a line break is source pretty-printing (indentation between
## tags), so it is dropped; a lone inline space (e.g. between "</span> <span>") has no
## line break and is kept, or "Hello"/"World" either side of it would run together.
static func _emit_text(raw: String, skip_depth: int) -> String:
	if skip_depth > 0 or raw == "":
		return ""
	if raw.strip_edges() == "" and raw.contains("\n"):
		return ""
	var decoded := _decode_entities(raw).replace("[", "[lb]")
	return _whitespace_regex.sub(decoded, " ", true)


static func _decode_entities(text: String) -> String:
	var result := text
	var start := 0
	while true:
		var m: RegExMatch = _numeric_entity_regex.search(result, start)
		if m == null:
			break
		var body: String = m.get_string(1)
		var code_point: int
		if body.begins_with("x") or body.begins_with("X"):
			code_point = ("0x" + body.substr(1)).hex_to_int()
		else:
			code_point = body.to_int()
		var replacement: String = char(code_point) if code_point > 0 else ""
		result = result.substr(0, m.get_start()) + replacement + result.substr(m.get_end())
		start = m.get_start() + replacement.length()
	result = result.replace("&nbsp;", " ")
	result = result.replace("&quot;", "\"")
	result = result.replace("&apos;", "'")
	result = result.replace("&lt;", "<")
	result = result.replace("&gt;", ">")
	result = result.replace("&amp;", "&")
	return result


## Trims stray leading/trailing whitespace left by block-tag spacing and collapses three
## or more consecutive newlines (nested block closes stacking up) down to one blank line.
static func _finalize(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	for i in lines.size():
		lines[i] = lines[i].strip_edges(false, true)  # trailing spaces only, keep leading indent
	var joined: String = "\n".join(lines)
	while joined.find("\n\n\n") != -1:
		joined = joined.replace("\n\n\n", "\n\n")
	return joined.strip_edges()
