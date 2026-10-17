## ConnectorScan — what a scene plugs into, read from the scene file's TEXT,
## without loading it.
##
## The spawn menu asks this of every object a mod registers, so that a mod's pad,
## gun or lead is offered on the card of every console it fits -- whoever made
## the console -- and so the stand-in it makes redundant can leave the card. A
## mod says nothing about any of this beyond the `connector` (or, for a pad, the
## `systemid`) on the nodes of its scene, which is also what makes it fit in the
## room. One declaration, read twice.
##
## Read as text because loading is what costs: a scene loads everything it
## names, and for the DualShock 2 that was its model and textures (200 ms) and
## its script compiled (46 ms), to read ten lines. The text is 0.6 ms. So nothing
## a scene refers to is loaded here: a node's script is followed by its `extends`
## line to the game class it comes from, which the game has loaded already, and a
## sub-scene is read only when it is another text scene (a model is skipped: it
## carries no plugs). A scene that is not text -- a binary .scn, which the mod
## packer never makes -- is loaded after all.
##
## It sees what the scene file says, not what a script decides at run time: the
## rule for authors is to set it on the node, in the scene.
class_name ConnectorScan
extends RefCounted

## What an object is to a card. A pad or a gun goes into a controller port; a
## lead has plugs on its cords.
const ROLE_CONTROLLER := "controller"
const ROLE_LIGHT_GUN := "light_gun"
const ROLE_LEAD := "lead"

## scene path -> {role, plugs}. A scene file does not change while the game runs.
static var _cache: Dictionary = {}
## script path -> {kind, default}: what a script makes a node, and the connector
## a plug of that class has when its scene names none.
static var _scripts: Dictionary = {}


## {role: String, plugs: PackedStringArray, systemid: String} for the scene at
## `path`: what its root is, the connectors of every plug it carries (its root's,
## for a pad), and for a pad or gun the console it was made for, its systemid --
## whatever its plug: a GunCon 2's is USB-A and it is still the PlayStation 2's.
## A scene that cannot be read is nothing.
static func of_scene(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var out := {"role": "", "plugs": PackedStringArray(), "systemid": ""}
	var nodes: Variant = _nodes(path)
	if nodes == null:
		var packed := ResourceLoader.load(path) as PackedScene if ResourceLoader.exists(path) else null
		if packed != null:
			_walk_state(packed.get_state(), out)
	else:
		_walk(nodes as Array, out, true)
	_cache[path] = out
	return out


static func clear_cache() -> void:
	_cache.clear()
	_scripts.clear()


static func _walk(nodes: Array, out: Dictionary, top: bool) -> void:
	for i in nodes.size():
		var node: Dictionary = nodes[i]
		var props: Dictionary = node["props"]
		var script_path := str(props.get("script", ""))
		var info := _script_info(script_path)
		_take(str(info["kind"]), props, info, out, top and i == 0)
		# Plugs further in, in a text sub-scene this one instances (a lead built of
		# a shared plug scene). Its root is this node, already taken above.
		var inner: Array = node.get("inner", [])
		if inner.size() > 1:
			_walk(inner.slice(1), out, false)


static func _take(kind: String, props: Dictionary, info: Dictionary, out: Dictionary, root: bool) -> void:
	if kind == ROLE_CONTROLLER or kind == ROLE_LIGHT_GUN:
		if not root:
			return
		out["role"] = kind
		var sysid := SystemIds.canonical(str(props.get("systemid", "")))
		out["systemid"] = sysid
		var c := str(props.get("connector", ""))
		if c.is_empty():
			c = Connectors.controller_port_of(sysid)
		if not c.is_empty():
			_add_plug(out, c)
	elif kind == ROLE_LEAD:
		if str(out["role"]).is_empty():
			out["role"] = ROLE_LEAD
		_add_plug(out, str(props.get("connector", info["default"])))


## A packed array is a value: one read out of the dictionary is a copy, so the
## whole array goes back in.
static func _add_plug(out: Dictionary, connector: String) -> void:
	var plugs: PackedStringArray = out["plugs"]
	if not plugs.has(connector):
		plugs.append(connector)
	out["plugs"] = plugs


# ── the scene's text ──────────────────────────────────────────────────────────

## The nodes of a text scene, in order, as [{props, inner}] where props holds the
## three properties read here (script as a path, connector, systemid). A node that
## instances another text scene has that scene's root's under its own, and that
## scene's nodes as `inner`. null when the file is not text.
static func _nodes(path: String) -> Variant:
	if not path.ends_with(".tscn"):
		return null
	var text := FileAccess.get_file_as_string(path)
	if not text.begins_with("[gd_scene"):
		return null
	var ext := {}
	var nodes: Array = []
	var current: Dictionary = {}
	for line: String in text.split("\n"):
		line = line.strip_edges()
		if line.begins_with("[ext_resource"):
			ext[_attr(line, "id")] = _attr(line, "path")
		elif line.begins_with("[node"):
			current = {"props": {}, "inner": []}
			var inst := _ref(line.get_slice("instance=", 1)) if line.contains("instance=") else ""
			var sub_path := str(ext.get(inst, ""))
			# An instanced text scene (an inherited scene's root, a shared plug):
			# its root's properties, with what this scene sets on it over them. A
			# model is not followed -- it carries no plugs.
			if sub_path.ends_with(".tscn") and sub_path != path:
				var inner: Variant = _nodes(sub_path)
				if inner != null and not (inner as Array).is_empty():
					current["props"] = ((inner as Array)[0]["props"] as Dictionary).duplicate()
					current["inner"] = inner
			nodes.append(current)
		elif line.begins_with("[") or current.is_empty():
			current = {} if line.begins_with("[") else current
		elif line.begins_with("script = "):
			current["props"]["script"] = str(ext.get(_ref(line), ""))
		elif line.begins_with("connector = "):
			current["props"]["connector"] = _string(line)
		elif line.begins_with("systemid = "):
			current["props"]["systemid"] = _string(line)
	return nodes


## `name="value"` out of a section header.
static func _attr(line: String, name: String) -> String:
	var at := line.find(" %s=\"" % name)
	if at < 0:
		return ""
	var start := at + name.length() + 3
	return line.substr(start, line.find("\"", start) - start)


## The id inside ExtResource("...").
static func _ref(text: String) -> String:
	var at := text.find("ExtResource(\"")
	if at < 0:
		return ""
	var start := at + 13
	return text.substr(start, text.find("\"", start) - start)


## The string a `key = "value"` line sets (StringName's &"..." too).
static func _string(line: String) -> String:
	var value := line.get_slice(" = ", 1).strip_edges().trim_prefix("&")
	return value.trim_prefix("\"").trim_suffix("\"")


# ── the node's script ─────────────────────────────────────────────────────────

## What a script makes a node, by the game class it comes from -- the nearest of
## LightGun, RetroController and RcaPlug up its chain -- and, for a plug, the
## connector its class gives it. No script is loaded: loading compiles it and
## whatever it preloads, and even a game class not yet used cost 41 ms. A script
## with no class name is followed by its `extends` line; a named one by the
## game's class list, which records each class's parent.
static func _script_info(path: String) -> Dictionary:
	if path.is_empty():
		return {"kind": "", "default": ""}
	if _scripts.has(path):
		return _scripts[path]
	var info := {"kind": "", "default": ""}
	var name := _class_of(path, 0)
	var first_plug := ""
	while not name.is_empty() and str(info["kind"]).is_empty():
		match name:
			"LightGun":
				info["kind"] = ROLE_LIGHT_GUN
			"RetroController":
				info["kind"] = ROLE_CONTROLLER
			"RcaPlug":
				info["kind"] = ROLE_LEAD
		if first_plug.is_empty() and name.ends_with("Plug"):
			first_plug = name
		name = str((_classes().get(name, {}) as Dictionary).get("base", ""))
	if info["kind"] == ROLE_LEAD:
		info["default"] = Connectors.PHONO
		# A subclass can set its own in _init (LinkPlug's "link_plug"), which no
		# declared default shows: one of the class says. Only then is it loaded.
		if first_plug != "RcaPlug" and not first_plug.is_empty():
			var script := load(str(_classes()[first_plug]["path"])) as Script
			var plug: Object = script.new()
			info["default"] = str(plug.get("connector"))
			(plug as Node).free()
	_scripts[path] = info
	return info


## The class a script at `path` is, or the first named class up its chain by its
## `extends` lines. "" for a chain that reaches an engine class.
static func _class_of(path: String, depth: int) -> String:
	_classes()
	if _class_at.has(path):
		return str(_class_at[path])
	if depth > 8:
		return ""
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if not line.begins_with("extends "):
			continue
		var base := line.trim_prefix("extends ").strip_edges()
		if base.begins_with("\""):
			return _class_of(base.trim_prefix("\"").get_slice("\"", 0), depth + 1)
		return base if _classes().has(base) else ""
	return ""


## The game's named classes: class -> {class, base, path}, and script path ->
## class. Read once.
static var _class_table: Dictionary = {}
static var _class_at: Dictionary = {}

static func _classes() -> Dictionary:
	if _class_table.is_empty():
		for row: Dictionary in ProjectSettings.get_global_class_list():
			_class_table[str(row["class"])] = {"class": str(row["class"]), "base": str(row["base"]),
				"path": str(row["path"])}
			_class_at[str(row["path"])] = str(row["class"])
	return _class_table


# ── a scene that is not text ──────────────────────────────────────────────────

static func _walk_state(state: SceneState, out: Dictionary) -> void:
	for i in state.get_node_count():
		var props := {}
		for p in state.get_node_property_count(i):
			var name := state.get_node_property_name(i, p)
			var value: Variant = state.get_node_property_value(i, p)
			props[name] = (value as Script).resource_path if name == "script" and value is Script else value
		var info := _script_info(str(props.get("script", "")))
		_take(str(info["kind"]), props, info, out, i == 0)
