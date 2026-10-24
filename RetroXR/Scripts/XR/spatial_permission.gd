## SpatialPermission — the player's consent to the game reading their room.
##
## Horizon OS keeps the room the player scanned in Space Setup, and the live depth
## of what is in front of them, behind one runtime permission (USE_SCENE, under
## an old and a new name) and its own "Allow access to spatial data?" dialog.
## RealRoom needs it for furniture to rest on, EnvironmentDepth for depth. It is
## asked for once a run, the first time the player is in passthrough with "Use
## Room Data in Passthrough" on (the default; off, plain passthrough asks nothing);
## the dialog is answered outside the app, so a holder re-checks has() when the
## app gets its focus back.
##
## A denied permission looks exactly like an empty room, so everything that
## needs it carries on without it, as the game did before.
class_name SpatialPermission
extends RefCounted

## Either name grants it: Horizon OS answers to the older on some releases and
## the newer on others.
const PERMISSIONS: PackedStringArray = [
	"com.oculus.permission.USE_SCENE",
	"horizonos.permission.USE_SCENE",
]

## The granted permissions, or null to ask the OS. A suite supplies them.
static var granted_source := Callable()
## Called with each permission asked for. A suite supplies one.
static var request_sink := Callable()
## Whether the player wants their room used, or null to read AppPrefs. A suite
## supplies one.
static var wanted_source := Callable()

static var _asked := false


## The player's choice (AppPrefs.passthrough_spatial): off, passthrough is only
## the view of the room, and nothing asks for or reads it.
static func is_wanted() -> bool:
	if wanted_source.is_valid():
		return bool(wanted_source.call())
	var tree := Engine.get_main_loop() as SceneTree
	var prefs := tree.root.get_node_or_null("AppPrefs") if tree != null and tree.root != null else null
	return prefs != null and bool(prefs.get("passthrough_spatial"))


## Wanted and allowed: what everything that reads the room asks.
static func usable() -> bool:
	return is_wanted() and has()


static func has() -> bool:
	var granted: PackedStringArray = granted_source.call() if granted_source.is_valid() \
		else OS.get_granted_permissions()
	for p in PERMISSIONS:
		if p in granted:
			return true
	return false


## Raise the consent dialog, once a run, and only for a player who wants their
## room used. True when it was raised now.
static func request_once() -> bool:
	if _asked or not is_wanted() or has():
		return false
	_asked = true
	for p in PERMISSIONS:
		if request_sink.is_valid():
			request_sink.call(p)
		else:
			OS.request_permission(p)
	return true


## Raise the consent dialog now, asked or not: the player pressed something that
## needs it.
static func request_now() -> void:
	_asked = true
	for p in PERMISSIONS:
		if request_sink.is_valid():
			request_sink.call(p)
		else:
			OS.request_permission(p)


## For suites.
static func reset() -> void:
	_asked = false
	granted_source = Callable()
	request_sink = Callable()
	wanted_source = Callable()
