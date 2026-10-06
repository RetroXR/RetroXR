## ModConnectors — the names of the sockets that mods from DIFFERENT authors
## have to agree on.
##
## A lead goes into a socket because the two name the same plug group, and that
## string is the whole agreement. Inside one mod it can be anything. Between two
## it cannot: an author who models a PlayStation 2 and another who models its AV
## lead each invent a name, and the lead does not go into the console. So the
## names that cross between mods are the game's, listed here, and a mod uses the
## one for its connector instead of making one up.
##
## The name IS the plug group: a socket script's and a plug script's
## plug_group() both return it, verbatim.
##
## A connector that is one mod's own business -- a bespoke dock, a private
## accessory port -- is namespaced "<mod_id>:<name>" like every other id a mod
## introduces, and is not listed here.
class_name ModConnectors
extends RefCounted

## name -> {platform, label}. Add a row when a connector first needs to cross
## between mods; never rename one, mods already out there return it.
const KNOWN := {
	"ps2_av_multi": {"platform": "ps2", "label": "PlayStation 2 AV MULTI OUT"},
}


## "" when `connector` is a name a mod may use, else why not.
static func problem(connector: String) -> String:
	if KNOWN.has(connector) or connector.contains(":"):
		return ""
	return "'%s' is not a connector the game names; use one from ModConnectors.KNOWN, " % connector \
		+ "or namespace your own as '<mod id>:%s'" % connector
