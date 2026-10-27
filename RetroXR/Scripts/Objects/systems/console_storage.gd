## ConsoleStorage — the lifecycle every per-console storage shares, so a machine
## walks one list instead of naming each one.
##
## Five children of RetroSystem put a console's memory where its core reads it
## and bring back what the core wrote: VmuStorage (a Dreamcast's VMUs),
## SegaCdStorage, SaturnStorage, ThreeDoStorage and XboxStorage. Each is built
## for EVERY machine and is inert on the consoles it is not for -- another
## machine asks this one's storage whether the shared folder is free
## (RetroSystem.sega_cd_storage() and friends), so it must always exist.
##
## RetroSystem calls these hooks in list order (RetroSystem._storages), and the
## order is part of the contract, because the storages write the same core
## option file and some of them the same save folder:
##
##   power_on      busy_elsewhere   one refusal card per storage, first one wins
##                 stage_for_run    BEFORE the forced options (they read the
##                                  cartridge image staging may only now create)
##                 stage_late       AFTER the forced and pak options -- where the
##                                  Dreamcast's slot pins always went
##   net_start     stage_for_run    only for storages whose stages_in_session()
##   first frame   after_first_frame
##   stop          after_stop       drain what the core wrote at unload
##   pad change    reapply
##   options       forced_options_for, merged over the hardware pins
##
## Every hook defaults to doing nothing, so a storage overrides only the phases
## it has. The concrete names each storage already had (stage_before_start,
## drain_after_stop, ...) stay public: suites and other machines call them.
class_name ConsoleStorage
extends Node

## The machine this belongs to. Set by RetroSystem in setup(), never by _ready:
## the node is added before the host can hand itself over.
var _host: RetroSystem = null


func setup(host: RetroSystem) -> void:
	_host = host


## The card title when another machine holds what this run would need ("Xbox in
## use"); only read when busy_elsewhere() answered something.
func busy_title() -> String:
	return ""


## Whether this machine may start on `core`.
## Returns "" when ok, else the reason.
func busy_elsewhere(_core: String) -> String:
	return ""


## Whether a lockstep session stages this storage too. False by default: a
## core that carries the memory in its savestate hands every peer the HOST's,
## and draining that back would write the host's saves over this console's.
func stages_in_session() -> bool:
	return false


## Before content starts, ahead of the forced core options.
func stage_for_run(_dir: String, _core: String) -> void:
	pass


## Before content starts, after the forced and pak options are written.
func stage_late(_dir: String, _core: String) -> void:
	pass


## The core has run one whole frame (SystemPorts.ensure_devices_bound).
func after_first_frame() -> void:
	pass


## The core has been told to stop; what it writes at unload lands after this.
func after_stop(_dir: String, _core: String) -> void:
	pass


## A controller's card slots changed (a VMU or a Memory Unit pushed or pulled).
func reapply(_ctrl: Node) -> void:
	pass


## The core options this storage pins for a run on `core`.
func forced_options_for(_core: String) -> Dictionary:
	return {}
