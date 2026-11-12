## Nintendo's HVC-003, the Famicom's RF switch: the RXR-003's job in a small white box.
##
## Routed exactly as RfSwitch: a black phono plug on the console lead (PlugA0) into
## the machine's RF OUT, the TV lead (PlugB0) into the set's aerial socket, and the
## aerial's input on the box (AntPort). The real TV lead is bare coax for a set's
## screw terminals; the game's sets take an F connector, so PlugB0 keeps the F plug.
## The aerial goes onto the coax one of the box's three screw terminals, which here
## is a CoaxPort standing UP out of the top: an Antenna's F plug goes down into it.
##
## Its own class only so a mod can dress it (class FamicomRfSwitch) without dressing
## the RXR-003, and so the spawn menu, a save and a test can tell the two apart.
## Everything else -- the two ropes, the tether, the save of the box's pose, aerial()
## and reached_set() -- is RfSwitch's, and every `is RfSwitch` check still holds.
##
## The scene (rf_switch_famicom.tscn) authors Body in RetroXR-models' glTF frame
## (meters, +Y up, base on y = 0, centered in X and Z), so the model's GLB goes on
## Body untransformed; the cord and terminal markers sit on the model's empties.
class_name FamicomRfSwitch
extends RfSwitch
