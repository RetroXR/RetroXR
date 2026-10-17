## ConnectorScan — what a scene plugs into, read from the scene file without
## building it.
##
## The spawn menu asks this of every object a mod registers, so that a mod's pad,
## gun or lead is offered on the card of every console it fits -- whoever made
## the console -- and so the stand-in it makes redundant can leave the card. A
## mod says nothing about any of this beyond the `connector` (or, for a pad, the
## `systemid`) on the nodes of its scene, which is also what makes it fit in the
## room. One declaration, read twice.
##
## Read from the SceneState: an object is not built until it is spawned, and a
## card is drawn far more often than that. Loading a scene still loads its
## models and textures, though, so what is read is also kept on disk, by the
## pack it came from (`stamp`): a mod's objects are read once per version, not
## once per boot, and never all at once when the first card opens. So it sees what the scene file says --
## a node's own properties, and those its script declares as defaults -- and not
## what a script decides at run time. That is the rule for authors: set it on the
## node, in the scene.
class_name ConnectorScan
extends RefCounted

## What an object is to a card. A pad or a gun goes into a controller port; a
## lead has plugs on its cords.
const ROLE_CONTROLLER := "controller"
const ROLE_LIGHT_GUN := "light_gun"
const ROLE_LEAD := "lead"

## scene path -> {role, plugs}. A scene file does not change while the game runs.
static var _cache: Dictionary = {}

## Where what was read is kept between runs: scene path -> {stamp, role, plugs}.
const DISK_CACHE := "user://connector_scan.json"
static var _disk: Dictionary = {}
static var _disk_read := false


## {role: String, plugs: PackedStringArray} for the scene at `path`: what its
## root is, and the connectors of every plug it carries (its root's, for a pad).
## A scene that will not load is nothing: {role: "", plugs: []}. `stamp` names
## the pack the scene is in (its mod's id, version and file time); with one, the
## answer is kept on disk and a later run with the same pack does not load it.
static func of_scene(path: String, stamp: String = "") -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	if not stamp.is_empty():
		var kept: Dictionary = _disk_cache().get(path, {})
		if str(kept.get("stamp", "")) == stamp:
			var known := {"role": str(kept.get("role", "")),
				"plugs": PackedStringArray(kept.get("plugs", []))}
			_cache[path] = known
			return known
	var out := {"role": "", "plugs": PackedStringArray()}
	var packed := ResourceLoader.load(path) as PackedScene if ResourceLoader.exists(path) else null
	if packed != null:
		_walk(packed.get_state(), out, true)
	_cache[path] = out
	if not stamp.is_empty():
		_disk[path] = {"stamp": stamp, "role": out["role"], "plugs": Array(out["plugs"])}
		JsonStore.write_dict(DISK_CACHE, _disk, "ConnectorScan")
	return out


static func _disk_cache() -> Dictionary:
	if not _disk_read:
		_disk_read = true
		_disk = JsonStore.read_dict(DISK_CACHE, "ConnectorScan")
	return _disk


static func clear_cache() -> void:
	_cache.clear()


static func _walk(state: SceneState, out: Dictionary, top: bool) -> void:
	for i in state.get_node_count():
		var props := _props(state, i)
		var sub := state.get_node_instance(i)
		if sub != null:
			# An instanced scene: its own root's properties, with what this scene
			# sets on the instance over them.
			var base := _props(sub.get_state(), 0)
			base.merge(props, true)
			props = base
		var script := props.get("script") as Script
		var kind := _kind(script)
		if kind == ROLE_CONTROLLER or kind == ROLE_LIGHT_GUN:
			if top and i == 0:
				out["role"] = kind
				var c := str(_value(props, script, "connector", ""))
				if c.is_empty():
					c = Connectors.controller_port_of(str(_value(props, script, "systemid", "")))
				if not c.is_empty():
					_add_plug(out, c)
		elif kind == ROLE_LEAD:
			if str(out["role"]).is_empty():
				out["role"] = ROLE_LEAD
			_add_plug(out, str(_value(props, script, "connector", Connectors.PHONO)))
		# Plugs further in, in a sub-scene this one instances (a lead built of a
		# shared plug scene).
		if sub != null and kind.is_empty():
			_walk(sub.get_state(), out, false)


## A packed array is a value: one read out of the dictionary is a copy, so the
## whole array goes back in.
static func _add_plug(out: Dictionary, connector: String) -> void:
	var plugs: PackedStringArray = out["plugs"]
	if not plugs.has(connector):
		plugs.append(connector)
	out["plugs"] = plugs


static func _props(state: SceneState, i: int) -> Dictionary:
	var props := {}
	for p in state.get_node_property_count(i):
		props[state.get_node_property_name(i, p)] = state.get_node_property_value(i, p)
	return props


## A property as the scene sets it, else as the node's script declares it.
static func _value(props: Dictionary, script: Script, prop: String, fallback: Variant) -> Variant:
	if props.has(prop):
		return props[prop]
	if script != null:
		var v: Variant = script.get_property_default_value(prop)
		if v != null:
			return v
	return fallback


## What a script makes a node, by the game class it comes from: the nearest of
## LightGun, RetroController and RcaPlug up its chain. A mod's script has no class
## name of its own, so it is its base that says.
static func _kind(script: Script) -> String:
	var s := script
	while s != null:
		match String(s.get_global_name()):
			"LightGun":
				return ROLE_LIGHT_GUN
			"RetroController":
				return ROLE_CONTROLLER
			"RcaPlug":
				return ROLE_LEAD
		s = s.get_base_script()
	return ""
