## ModRecord — what the app knows about one installed mod.
##
## ModManager kept this as a Dictionary whose own comment called it
## "ModRecord-ish", and the Mods page reached into it by string key. The fields
## were never in doubt — they are set in one place and read in two — so the
## comment was promising a type that had simply never been written.
##
## Most of a record is filled in WITHOUT mounting the pack: id, manifest, size,
## file count and thumbnail are all read from the closed container, because the
## page has to show a disabled mod's name and art while the player is deciding
## whether to trust it. `api` is the only field that requires the pack to be
## mounted, and stays null until it is.
class_name ModRecord
extends RefCounted

## What happened to one mod this boot.
enum Status {
	DISABLED,       ## found, not enabled — the default for anything new
	PENDING,        ## enabled since the last launch; mounts next restart
	LOADED,         ## mounted and registered
	REFUSED,        ## failed a check, so it was never mounted
	FAILED,         ## mounted, but its entry script did not run
}

var id: String = ""
var manifest: ModManifest = null
## The container on disk — the .zip or .pck the player installed.
var path: String = ""
var size: int = 0
## How many members the container holds, shown on the page as a sanity check.
var files: int = 0
var status: Status = Status.DISABLED
## Why a mod is REFUSED or FAILED, or a note about what a LOADED one shadows.
## Empty for the ordinary case.
var reason: String = ""
## The mod's own entry object. Null until the pack is mounted and its script has
## run, which is never for anything that did not reach LOADED.
var api: ModApi = null
var thumbnail: Texture2D = null
## The pack was handed to ProjectSettings.load_resource_pack this session. True
## for LOADED and for FAILED alike, and it is what decides whether the file can
## be replaced or deleted now or only at the next launch: a mounted container
## stays open for as long as the app runs.
var mounted := false
## Version of an update that is downloaded and waiting for the next launch, ""
## for none. The record keeps describing the pack that is actually mounted, so
## the netplay fingerprint goes on telling the truth about this session.
var update_staged: String = ""
## What that waiting pack is, for the page: its own picture, size and file count.
## The page shows these beside the running pack's, so a mod that is about to be
## replaced is not described only by the copy that is on its way out.
var update_thumbnail: Texture2D = null
var update_size: int = 0
var update_files: int = 0
## The player removed this mod while it was mounted; the file goes at the next
## launch.
var removal_staged := false


## Mark a mod as refused or failed, with the reason shown on the Mods page.
func refuse(why: String) -> void:
	status = Status.REFUSED
	reason = why


func fail(why: String) -> void:
	status = Status.FAILED
	reason = why
