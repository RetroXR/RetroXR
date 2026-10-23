## SpatialPermission — the player's consent to the game reading their room.
##
## Horizon OS keeps the room the player scanned in Space Setup, and the live depth
## of what is in front of them, behind one runtime permission (USE_SCENE, under
## an old and a new name) and its own "Allow access to spatial data?" dialog.
## RealRoom needs it for furniture to rest on, EnvironmentDepth for depth. It is
## asked for once a run, the first time the player is in passthrough; the dialog
## is answered outside the app, so a holder re-checks has() when the app gets its
## focus back.
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

static var _asked := false


static func has() -> bool:
	var granted: PackedStringArray = granted_source.call() if granted_source.is_valid() \
		else OS.get_granted_permissions()
	for p in PERMISSIONS:
		if p in granted:
			return true
	return false


## Raise the consent dialog, once a run. True when it was raised now.
static func request_once() -> bool:
	if _asked or has():
		return false
	_asked = true
	for p in PERMISSIONS:
		if request_sink.is_valid():
			request_sink.call(p)
		else:
			OS.request_permission(p)
	return true


## For suites.
static func reset() -> void:
	_asked = false
	granted_source = Callable()
	request_sink = Callable()
