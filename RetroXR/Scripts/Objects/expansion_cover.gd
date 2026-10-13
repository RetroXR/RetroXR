## ExpansionCover — the little plastic lid over a console's expansion bay.
##
## The Nintendo 64's is the one this exists for: the Jumper Pak lives under a
## cover you PULL OFF completely and put down, not a hinged door that stays
## attached. So it is a pickable in its own right — it can be carried across the
## room, left on a table, and lost, exactly like the real thing.
##
## It does nothing at all except be present or absent. While it is seated in a
## console's cover slot, that console's expansion socket is shut: no hand can
## reach the pak, and the pak is out of sight. Taking it off is what opens the
## bay. The gate lives on the model that owns the slot (see
## RetroSystemModelNintendo64), not here, because only the model knows which
## socket this particular lid is covering.
class_name ExpansionCover
extends XRToolsPickable

## Must be in this group to snap into a console's cover slot — the same
## arrangement a memory card and its slots use.
const GROUP := "expansion_cover"

## Which of its console's colors this lid is, by the ids RetroSystem.
## model_variant takes; empty for a lid nothing has colored. The game only
## keeps it: a model whose lid comes in colors sets it, and a save carries it,
## so a lid lying loose is still its own color when the room loads, and one
## put on another console does not turn that console's.
var model_variant: String = ""
