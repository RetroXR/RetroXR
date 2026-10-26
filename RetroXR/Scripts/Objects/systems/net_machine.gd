## NetMachine — the contract between a netplay session and a machine it runs,
## written down in one place instead of in forty has_method() probes.
##
## Three kinds of node are machines to NetplaySession: a RetroSystem, a Game Boy
## Printer (GbPrinter) and a Dreamcast VMU running on its own (VmuCard). They
## share no base class -- a console is a pickable rigid body, a printer and a VMU
## are peripherals with a Libretro of their own -- so the contract is by NAME,
## and this is that list. Every REQUIRED method below is implemented by all
## three; system_tests checks it against their scripts, so a method dropped or
## renamed on one of them goes red there rather than as a silent default in a
## session.
##
## OPTIONAL methods are RetroSystem's alone (link cables, cartridges, ports);
## the session asks for them with has() and falls back the way each call site
## documents. A machine missing a REQUIRED one is a bug, and has() says so
## once per script in the log.
##
## Reading the protocol:
##   net_boot_failure         (var)  why net_prepare_boot last refused, in words
##   get_libretro_node()             the Libretro the session drives
##   net_rom_md5()                   the content's hash, "" with none
##   net_boot_spec(core)             how to reproduce this boot on a peer ({} = cannot)
##   net_prepare_boot(spec)          recreate that boot here; false = cannot
##   net_sram_file_bytes()           the save the host ships at cold start
##   net_set_sram(path, data)        the save every peer boots from
##   net_start_core(core, mask, frame, options) -> Libretro   start under the gate
##   net_stop_core()                 stop it and clear the gate
##   net_play_reset()                the visual half of a scheduled reset
class_name NetMachine
extends RefCounted

const REQUIRED_PROPERTIES: PackedStringArray = ["net_boot_failure"]

const REQUIRED: PackedStringArray = [
	"get_libretro_node", "net_rom_md5", "net_boot_spec", "net_prepare_boot",
	"net_sram_file_bytes", "net_set_sram", "net_start_core", "net_stop_core",
	"net_play_reset",
]

const OPTIONAL: PackedStringArray = [
	"net_resolve_rom", "net_resolve_card", "net_link_group", "net_link_buses",
	"net_refresh_link_cables", "port_holders", "resolve_core_name", "get_model",
]

## Scripts already reported as missing a REQUIRED method, so a session asking
## every frame logs it once.
static var _reported: Dictionary = {}


## The REQUIRED methods and properties `machine` lacks; empty for a whole one.
static func missing(machine: Object) -> PackedStringArray:
	var out := PackedStringArray()
	if machine == null:
		out.append("<null machine>")
		return out
	for method in REQUIRED:
		if not machine.has_method(method):
			out.append(method + "()")
	for property in REQUIRED_PROPERTIES:
		if not (property in machine):
			out.append(property)
	return out


## The same, asked of a SCRIPT rather than an instance -- what system_tests uses,
## since building a console or a printer needs a scene.
static func missing_in_script(script: Script) -> PackedStringArray:
	var out := PackedStringArray()
	if script == null:
		out.append("<null script>")
		return out
	var methods := {}
	var properties := {}
	var walk: Script = script
	while walk != null:
		for m: Dictionary in walk.get_script_method_list():
			methods[str(m.get("name", ""))] = true
		for p: Dictionary in walk.get_script_property_list():
			properties[str(p.get("name", ""))] = true
		walk = walk.get_base_script()
	for method in REQUIRED:
		if not methods.has(method):
			out.append(method + "()")
	for property in REQUIRED_PROPERTIES:
		if not properties.has(property):
			out.append(property)
	return out


## Whether `machine` answers `method`, for a session about to call it. A REQUIRED
## method that is missing is logged (once per script) as the contract breach it
## is, rather than falling quietly through to the caller's default.
static func has(machine: Object, method: String) -> bool:
	if machine == null:
		return false
	if machine.has_method(method):
		return true
	if REQUIRED.has(method):
		var script: Script = machine.get_script() as Script
		var who: String = script.resource_path if script != null else machine.get_class()
		var key := "%s#%s" % [who, method]
		if not _reported.has(key):
			_reported[key] = true
			push_error("[Netplay] machine %s lacks REQUIRED NetMachine.%s()" % [who, method])
	return false
